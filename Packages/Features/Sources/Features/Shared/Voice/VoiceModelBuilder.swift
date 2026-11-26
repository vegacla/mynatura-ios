import Core
import Foundation
import Speech

/// Archivos del modelo de lenguaje propio ya preparado (Sendable: solo rutas).
struct CustomModelFiles: Sendable, Equatable {
    let localeIdentifier: String
    let version: String
    let languageModel: URL
    let vocabulary: URL
}

/// Arma el modelo de lenguaje propio en el iPhone (V6, iOS 17): frases → `SFCustomLanguageModelData` → export →
/// `prepareCustomLanguageModel`. Se guarda en Caches por idioma y versión; si las frases no cambian, se reutiliza.
/// Solo sirve con reconocimiento en el dispositivo. Sin aislamiento: los callbacks de Speech llegan en otros hilos.
enum VoiceModelBuilder {
    static let clientIdentifier = "cl.mynatura.app.voice"

    static var directory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return caches.appendingPathComponent("VoiceModel", isDirectory: true)
    }

    static func build(localeIdentifier: String, phrases: [VoicePhrase], version: String) async throws -> CustomModelFiles {
        let base = directory.appendingPathComponent("\(localeIdentifier)-\(version)", isDirectory: true)
        let files = CustomModelFiles(localeIdentifier: localeIdentifier, version: version,
                                     languageModel: base.appendingPathComponent("lm.bin"),
                                     vocabulary: base.appendingPathComponent("vocab.bin"))
        let manager = FileManager.default
        if manager.fileExists(atPath: files.languageModel.path), manager.fileExists(atPath: files.vocabulary.path) {
            return files
        }

        try manager.createDirectory(at: base, withIntermediateDirectories: true)
        let asset = base.appendingPathComponent("data.bin")
        let data = SFCustomLanguageModelData(locale: Locale(identifier: localeIdentifier),
                                             identifier: clientIdentifier, version: version)
        for phrase in phrases {
            data.insert(phraseCount: SFCustomLanguageModelData.PhraseCount(phrase: phrase.phrase, count: phrase.count))
        }
        try await data.export(to: asset)
        try await prepare(asset: asset, files: files)
        try? manager.removeItem(at: asset)
        removeOtherVersions(keeping: base)
        return files
    }

    static func configuration(for files: CustomModelFiles) -> SFSpeechLanguageModel.Configuration {
        SFSpeechLanguageModel.Configuration(languageModel: files.languageModel, vocabulary: files.vocabulary)
    }

    private static func prepare(asset: URL, files: CustomModelFiles) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            SFSpeechLanguageModel.prepareCustomLanguageModel(for: asset, clientIdentifier: clientIdentifier,
                                                             configuration: configuration(for: files)) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    /// Borra modelos de versiones anteriores para no acumular archivos.
    private static func removeOtherVersions(keeping current: URL) {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for entry in entries where entry.standardizedFileURL != current.standardizedFileURL {
            try? manager.removeItem(at: entry)
        }
    }
}
