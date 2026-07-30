import Foundation

/// Built-in transcription model registry.
///
/// The model list lives directly in source rather than as a JSON resource so
/// the binary stays self-contained — no `Bundle.module` lookup, no per-target
/// resource bundle to ship alongside the executable.
enum ModelRegistry {
    static let shared: [TranscriptionModel] = [
        TranscriptionModel(
            id: "whisper-large-v3",
            displayName: "Whisper Large v3 — Best accuracy",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-large-v3-v20240930_626MB",
            sizeMB: 626,
            languages: ["es", "en"],
            languageMode: .automatic,
            recommended: true
        ),
        TranscriptionModel(
            id: "whisper-small",
            displayName: "Whisper Small — Balanced",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-small",
            sizeMB: 486,
            languages: ["es", "en"],
            languageMode: .automatic,
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-base",
            displayName: "Whisper Base — Lightweight",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-base",
            sizeMB: 147,
            languages: ["es", "en"],
            languageMode: .automatic,
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-base.en",
            displayName: "Whisper Base — English only",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-base.en",
            sizeMB: 145,
            languages: ["en"],
            languageMode: .englishOnly,
            recommended: false
        ),
        TranscriptionModel(
            id: "whisper-small.en",
            displayName: "Whisper Small — English only",
            engine: .whisperKit,
            whisperKitID: "openai_whisper-small.en",
            sizeMB: 486,
            languages: ["en"],
            languageMode: .englishOnly,
            recommended: false
        ),
    ]

    static func find(_ id: String) -> TranscriptionModel? {
        shared.first { $0.id == id }
    }

    static func recommended() -> TranscriptionModel? {
        shared.first { $0.recommended } ?? shared.first
    }
}
