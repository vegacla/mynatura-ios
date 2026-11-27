import Core
import Foundation

/// Frases no entendidas, guardadas solo en este iPhone si la consultora lo activa (Ajustes › Voz).
enum VoicePhraseLog {
    static let key = "voice.unrecognizedPhrases"

    static var entries: [UnrecognizedPhrases.Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([UnrecognizedPhrases.Entry].self, from: data)) ?? []
    }

    static func append(_ text: String) {
        let updated = UnrecognizedPhrases.appending(text, to: entries, date: .now)
        UserDefaults.standard.set(try? JSONEncoder().encode(updated), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
