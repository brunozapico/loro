import Foundation

enum Engine: String, Codable {
    case whisperKit
    case parakeet
}

enum TranscriptionLanguageMode: String, Codable {
    case automatic
    case englishOnly

    var displayName: String {
        switch self {
        case .automatic:
            return "Spanish + English (automatic)"
        case .englishOnly:
            return "English only"
        }
    }
}

struct TranscriptionModel: Codable {
    let id: String
    let displayName: String
    let engine: Engine
    /// Engine-specific identifier (e.g. "openai_whisper-base.en" for WhisperKit).
    let whisperKitID: String?
    let sizeMB: Int
    let languages: [String]
    let languageMode: TranscriptionLanguageMode
    let recommended: Bool
}

struct ModelsManifest: Codable {
    let models: [TranscriptionModel]
}
