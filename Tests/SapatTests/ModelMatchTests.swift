import XCTest
@testable import Sapat

/// The configured model id (`qwen/qwen3-8b`) rarely equals the id LM Studio reports for the
/// download `lms get` actually lands (`lmstudio-community/Qwen3-8B-MLX-4bit`). These verify
/// the normalized matcher bridges that gap without matching the wrong model.
final class ModelMatchTests: XCTestCase {

    func testNormalizationStripsPathPunctuationAndCase() {
        XCTAssertEqual(LMStudioClient.normalizedModelKey("qwen/qwen3-8b"), "qwen38b")
        XCTAssertEqual(LMStudioClient.normalizedModelKey("lmstudio-community/Qwen3-8B-MLX-4bit"), "qwen38bmlx4bit")
    }

    func testConfiguredKeyMatchesActualDownloadId() {
        XCTAssertTrue(LMStudioClient.modelsMatch("qwen/qwen3-8b", "lmstudio-community/Qwen3-8B-MLX-4bit"))
        XCTAssertTrue(LMStudioClient.modelsMatch("qwen/qwen3-8b", "qwen3-8b"))
        XCTAssertTrue(LMStudioClient.modelsMatch("qwen/qwen3-8b", "qwen/qwen3-8b-instruct"))
    }

    func testDoesNotMatchDifferentModels() {
        XCTAssertFalse(LMStudioClient.modelsMatch("qwen/qwen3-8b", "qwen/qwen3-80b"))
        XCTAssertFalse(LMStudioClient.modelsMatch("qwen/qwen3-8b", "qwen/qwen3-4b"))
        XCTAssertFalse(LMStudioClient.modelsMatch("qwen/qwen3-8b", "meta-llama/Llama-3-8B"))
        // The user's leftover 27B partial must not be mistaken for the 8B.
        XCTAssertFalse(LMStudioClient.modelsMatch("qwen/qwen3-8b", "lmstudio-community/Qwen3.6-27B-MLX-8bit"))
    }

    func testEmptyIsNeverAMatch() {
        XCTAssertFalse(LMStudioClient.modelsMatch("", "qwen/qwen3-8b"))
        XCTAssertFalse(LMStudioClient.modelsMatch("qwen/qwen3-8b", "/"))
    }
}
