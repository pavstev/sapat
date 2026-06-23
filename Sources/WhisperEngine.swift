import Foundation
import WhisperKit

/// Thin wrapper around WhisperKit. An `actor` so the (non-`Sendable`) `WhisperKit`
/// pipeline is only ever touched from one isolation domain.
///
/// We run two kinds of passes over the same recording:
///   - `.transcribe` with `language: "sr"` → the Serbian text we display.
///   - `.translate`                        → English (Whisper's offline fallback).
actor WhisperEngine {
    private var pipe: WhisperKit?

    var isLoaded: Bool { pipe != nil }

    /// Loads the model, downloading it from Hugging Face on first run (~250 MB for
    /// `openai_whisper-small`). Blocks until the model is ready to use.
    func load(model: String) async throws {
        guard pipe == nil else { return }
        pipe = try await WhisperKit(WhisperKitConfig(model: model))
    }

    /// Runs one transcription/translation pass and returns the trimmed text.
    func run(audioPath: String, task: DecodingTask, language: String?) async throws -> String {
        guard let pipe else { throw WhisperEngineError.notLoaded }
        let options = DecodingOptions(task: task, language: language)
        // WhisperKit 1.0.0 returns a single optional `TranscriptionResult`.
        // If a future version returns `[TranscriptionResult]`, change the next line to:
        //   let result = try await pipe.transcribe(audioPath: audioPath, decodeOptions: options)
        //   return result.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        let result = try await pipe.transcribe(audioPath: audioPath, decodeOptions: options)
        return (result?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum WhisperEngineError: LocalizedError {
    case notLoaded

    var errorDescription: String? {
        switch self {
        case .notLoaded: return "The speech model isn't loaded yet."
        }
    }
}
