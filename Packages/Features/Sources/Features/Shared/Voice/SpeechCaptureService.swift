import AVFoundation
import Foundation
import Observation
import Speech

/// Captura de voz → texto (§5.3 de docs/voice-interaction-proposal.md).
/// Prefiere el reconocimiento en el dispositivo (sin red, el audio no sale del iPhone); el servidor de Apple
/// solo se usa si la persona lo permitió. El audio nunca se guarda.
///
/// Dos modos:
/// - **Mantener presionado**: una frase por pulsación (`start` / `stop`).
/// - **Continuo** (`startContinuous`): sigue escuchando; cada pausa de 1,5 s cierra una frase y se reinicia el
///   reconocimiento; 8 s de silencio lo apagan. "listo" lo apaga desde la pantalla.
@MainActor
@Observable
final class SpeechCaptureService {
    enum State: Equatable {
        case idle
        case starting
        case listening
        /// Se soltó el botón; esperando el texto final.
        case finishing
        case failed(String)
    }

    /// Una frase terminada.
    struct Utterance: Equatable {
        let id: Int
        let text: String
    }

    /// Variantes de español probadas en orden; la primera con modelo local gana.
    static let localeIdentifiers = ["es-CL", "es-419", "es-US", "es-MX", "es-ES"]
    /// Pausa que cierra una frase en modo continuo.
    static let pauseToCommit: TimeInterval = 1.5
    /// Silencio que apaga el modo continuo.
    static let silenceToStop: TimeInterval = 8

    private(set) var state: State = .idle
    private(set) var transcript = ""
    private(set) var lastUtterance: Utterance?
    /// El reconocimiento en curso usa servidores de Apple.
    private(set) var usesServer = false
    private(set) var isContinuous = false

    private let pipeline = SpeechPipeline()
    private var session: RecognitionSession?
    private var generation = 0
    private var stopRequested = false
    private var lastActivity = Date()
    private var monitor: Task<Void, Never>?

    var isListening: Bool { state == .listening || state == .starting }

    // MARK: Mantener presionado

    func start(contextualStrings: [String], allowServer: Bool) async {
        guard state != .listening, state != .starting else { return }
        state = .starting
        stopRequested = false
        transcript = ""

        guard await SpeechPipeline.requestPermissions() else {
            isContinuous = false
            state = .failed("Activa el micrófono y el reconocimiento de voz para MyNatura en Ajustes del iPhone.")
            return
        }
        guard let choice = Self.chooseRecognizer(allowServer: allowServer) else {
            isContinuous = false
            state = .failed(allowServer
                ? "El reconocimiento de voz no está disponible ahora. Intenta de nuevo en un momento."
                : "Este iPhone no tiene reconocimiento de voz en español sin conexión. Puedes permitir los servidores de Apple abajo.")
            return
        }
        session = RecognitionSession(recognizer: choice.recognizer, onDevice: choice.onDevice,
                                     contextualStrings: contextualStrings)
        usesServer = !choice.onDevice

        if beginRecognition() {
            state = .listening
            lastActivity = Date()
            if stopRequested { stop() }
        }
    }

    /// Soltar el botón: termina de escuchar y espera el texto final (máx. 2 s).
    func stop() {
        if isContinuous {
            stopContinuous()
            return
        }
        switch state {
        case .starting:
            stopRequested = true
        case .listening:
            pipeline.stop()
            state = .finishing
            let current = generation
            let target = WeakService(self)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                target.service?.finishIfStillWaiting(generation: current)
            }
        default:
            break
        }
    }

    func cancel() {
        isContinuous = false
        monitor?.cancel()
        monitor = nil
        generation += 1
        pipeline.cancel()
        state = .idle
        transcript = ""
    }

    // MARK: Continuo

    /// Pasa a escuchar sin manos. Se llama justo después de `start` (con un toque corto).
    func startContinuous() {
        guard !isContinuous else { return }
        isContinuous = true
        stopRequested = false
        lastActivity = Date()
        let target = WeakService(self)
        monitor?.cancel()
        monitor = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let service = target.service, service.isContinuous else { return }
                service.tick()
            }
        }
    }

    func stopContinuous() {
        guard isContinuous else { return }
        isContinuous = false
        monitor?.cancel()
        monitor = nil
        switch state {
        case .listening:
            pipeline.stop()
            state = .finishing
            let current = generation
            let target = WeakService(self)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                target.service?.finishIfStillWaiting(generation: current)
            }
        case .starting:
            stopRequested = true
        default:
            break
        }
    }

    private func tick() {
        guard state == .listening else { return }
        let idle = Date().timeIntervalSince(lastActivity)
        if !transcript.isEmpty, idle >= Self.pauseToCommit {
            commitAndRestart()
        } else if transcript.isEmpty, idle >= Self.silenceToStop {
            isContinuous = false
            monitor?.cancel()
            monitor = nil
            generation += 1
            pipeline.cancel()
            state = .idle
        }
    }

    /// Entrega la frase y reinicia el reconocimiento para la siguiente (el texto parcial vuelve a cero).
    private func commitAndRestart() {
        publish(transcript)
        transcript = ""
        lastActivity = Date()
        pipeline.cancel()
        if !beginRecognition() {
            isContinuous = false
            monitor?.cancel()
            monitor = nil
        }
    }

    // MARK: Reconocimiento

    /// Arranca audio + reconocimiento con la sesión actual. Devuelve false (y deja el error) si falla.
    private func beginRecognition() -> Bool {
        guard let session else {
            state = .failed("El reconocimiento de voz no está disponible ahora.")
            return false
        }
        generation += 1
        let current = generation
        let target = WeakService(self)
        do {
            try pipeline.start(
                recognizer: session.recognizer,
                onDevice: session.onDevice,
                contextualStrings: session.contextualStrings,
                onResult: { text, isFinal in
                    Task { @MainActor in target.service?.receive(text, isFinal: isFinal, generation: current) }
                },
                onError: { message in
                    Task { @MainActor in target.service?.fail(message, generation: current) }
                })
            return true
        } catch {
            pipeline.cancel()
            state = .failed("No se pudo usar el micrófono. Cierra otras apps que lo estén usando e intenta de nuevo.")
            return false
        }
    }

    fileprivate func receive(_ text: String, isFinal: Bool, generation: Int) {
        guard generation == self.generation else { return }
        if text != transcript {
            transcript = text
            lastActivity = Date()
        }
        guard isFinal else { return }
        if isContinuous, state == .listening {
            if !transcript.isEmpty { commitAndRestart() }
        } else {
            finish()
        }
    }

    fileprivate func fail(_ message: String, generation: Int) {
        guard generation == self.generation else { return }
        if isContinuous, state == .listening, !transcript.isEmpty {
            commitAndRestart()
            return
        }
        // Tras soltar el botón, un error suele significar "no hubo más audio": vale lo que ya se oyó.
        if state == .finishing || !transcript.isEmpty {
            finish()
        } else {
            isContinuous = false
            monitor?.cancel()
            monitor = nil
            pipeline.cancel()
            state = .failed(message)
        }
    }

    fileprivate func finishIfStillWaiting(generation: Int) {
        guard generation == self.generation, state == .finishing else { return }
        finish()
    }

    private func finish() {
        let text = transcript
        generation += 1
        pipeline.cancel()
        state = .idle
        transcript = ""
        publish(text)
    }

    private func publish(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lastUtterance = Utterance(id: (lastUtterance?.id ?? 0) + 1, text: trimmed)
    }

    private struct RecognizerChoice {
        let recognizer: SFSpeechRecognizer
        let onDevice: Bool
    }

    private struct RecognitionSession {
        let recognizer: SFSpeechRecognizer
        let onDevice: Bool
        let contextualStrings: [String]
    }

    private static func chooseRecognizer(allowServer: Bool) -> RecognizerChoice? {
        let recognizers = localeIdentifiers.compactMap { SFSpeechRecognizer(locale: Locale(identifier: $0)) }
        if let local = recognizers.first(where: { $0.supportsOnDeviceRecognition }) {
            return RecognizerChoice(recognizer: local, onDevice: true)
        }
        if allowServer, let server = recognizers.first(where: { $0.isAvailable }) {
            return RecognizerChoice(recognizer: server, onDevice: false)
        }
        return nil
    }
}

/// Audio y reconocimiento fuera del actor principal: el tap de audio y los callbacks de Speech
/// llegan en hilos propios, así que se crean aquí (sin aislamiento) y solo pasan textos al MainActor.
final class SpeechPipeline: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    static func requestPermissions() async -> Bool {
        let speech = await speechAuthorization()
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    private static func speechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    func start(recognizer: SFSpeechRecognizer, onDevice: Bool, contextualStrings: [String],
               onResult: @escaping @Sendable (String, Bool) -> Void,
               onError: @escaping @Sendable (String) -> Void) throws {
        cancel()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = onDevice
        request.contextualStrings = contextualStrings
        request.taskHint = .dictation
        request.addsPunctuation = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let box = RequestBox(request)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            box.request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            }
            if error != nil {
                onError("No te escuché bien. Intenta de nuevo.")
            }
        }

        lock.lock()
        self.request = request
        self.task = task
        lock.unlock()
    }

    /// Deja de grabar; el reconocimiento entrega su resultado final.
    func stop() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        lock.lock()
        let request = self.request
        lock.unlock()
        request?.endAudio()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancel() {
        stop()
        lock.lock()
        let task = self.task
        self.task = nil
        self.request = nil
        lock.unlock()
        task?.cancel()
    }
}

/// Referencia débil que cruza a los callbacks de audio sin retener el servicio.
private final class WeakService: @unchecked Sendable {
    weak var service: SpeechCaptureService?

    init(_ service: SpeechCaptureService) {
        self.service = service
    }
}

/// El request no es Sendable, pero solo se usa para entregarle buffers desde el tap de audio.
private final class RequestBox: @unchecked Sendable {
    let request: SFSpeechAudioBufferRecognitionRequest

    init(_ request: SFSpeechAudioBufferRecognitionRequest) {
        self.request = request
    }
}
