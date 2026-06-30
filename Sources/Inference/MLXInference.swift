#if canImport(MLXLLM)
import Foundation
import MLXLLM
import MLXLMCommon

/// In-process LLM inference on Apple Silicon via MLX — the **default** engine. Loads a small,
/// strong, quantized reasoner once and serves the whole `ThoughtPipeline` locally: no sidecar,
/// no localhost server, no other apps. This is what makes Šapat self-contained (D1).
///
/// Compiled only when the MLX packages are present. The build uses `xcodebuild` (Xcode compiles
/// MLX's Metal kernels into `default.metallib`; a plain `swift build` under the Command Line
/// Tools cannot, which is why this file is guarded by `#if canImport(MLXLLM)`). The model is
/// cached outside the app bundle, so it survives in-place updates and is fetched once.
///
/// ⚠️ The model-load + generate calls target the `mlx-swift-lm` (MLXLLM / MLXLMCommon) API.
/// When wiring the package, validate them against the pinned version — that is the
/// version-sensitive surface — then this becomes the live default backend.
actor MLXInference: Inference {
    /// Default reasoner: a small, strong, Apache-2.0 quantized chat model (3–4B class).
    static let defaultModelID = "mlx-community/Qwen3-4B-4bit"

    private let modelID: String
    private let maxContext: Int
    private var container: ModelContainer?

    init(modelID: String = MLXInference.defaultModelID, contextWindow: Int = 8192) {
        self.modelID = modelID
        self.maxContext = contextWindow
    }

    func prepare(onStatus: @escaping @Sendable (String?) -> Void) async throws {
        guard container == nil else { return }
        onStatus("Loading the on-device model…")
        do {
            let configuration = ModelConfiguration(id: modelID)
            container = try await LLMModelFactory.shared.loadContainer(configuration: configuration) { progress in
                onStatus("Downloading the on-device model… \(Int(progress.fractionCompleted * 100))%")
            }
            onStatus(nil)
        } catch {
            onStatus(nil)
            throw InferenceError.notReady("Couldn't load the on-device model: \(error.localizedDescription)")
        }
    }

    func generate(_ request: InferenceRequest) async throws -> String {
        let container = try await readyContainer()
        let chat: [Chat.Message] = request.messages.map { message in
            switch message.role {
            case .system: return .system(message.content)
            case .user: return .user(message.content)
            case .assistant: return .assistant(message.content)
            }
        }
        let parameters = GenerateParameters(
            maxTokens: request.maxTokens ?? 1024,
            temperature: Float(request.temperature))
        return try await container.perform { (context: ModelContext) in
            let input = try await context.processor.prepare(input: UserInput(chat: chat))
            var text = ""
            for await generation in try MLXLMCommon.generate(input: input, parameters: parameters, context: context) {
                if let chunk = generation.chunk { text += chunk }
            }
            return text
        }
    }

    var contextWindow: Int { get async { maxContext } }

    private func readyContainer() async throws -> ModelContainer {
        if let container { return container }
        try await prepare(onStatus: { _ in })
        guard let container else { throw InferenceError.notReady("The on-device model isn't loaded.") }
        return container
    }
}
#endif
