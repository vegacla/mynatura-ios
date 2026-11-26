import AVFoundation
import Foundation

/// Lee respuestas en voz alta (AVSpeechSynthesizer, voz es-CL si existe). Al terminar libera el audio
/// para que la música u otras apps vuelvan a su volumen.
final class VoiceSpeaker: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static func voice() -> AVSpeechSynthesisVoice? {
        for identifier in ["es-CL", "es-419", "es-MX", "es-US", "es-ES"] {
            if let voice = AVSpeechSynthesisVoice(language: identifier) { return voice }
        }
        return nil
    }

    func speak(_ text: String) {
        stop()
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: .duckOthers)
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
