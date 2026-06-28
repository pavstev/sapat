import XCTest
@testable import Sapat

/// The `lms get`/`lms load` progress lines arrive with a spinner and ANSI escapes; these
/// verify we extract a clean "label — NN% · X / Y · ETA …" for the UI, and ignore noise.
final class DownloadProgressTests: XCTestCase {

    func testParsesRealLmsGetLine() {
        let raw = "⠴ [████████████████████▎ ] 91.48% | 4.23 GB / 4.62 GB | 2.70 MB/s | ETA 02:26          \u{1B}[u\u{1B}[?25l"
        let status = LMStudioManager.progressStatus(from: raw, label: "Downloading refinement model")
        XCTAssertEqual(status, "Downloading refinement model — 91% · 4.23 GB / 4.62 GB · ETA 02:26")
    }

    func testRoundsPercentAndKeepsLabel() {
        let status = LMStudioManager.progressStatus(from: "12.0% | 0.5 GB / 4.6 GB | ETA 10:00", label: "Loading refinement model")
        XCTAssertEqual(status, "Loading refinement model — 12% · 0.5 GB / 4.6 GB · ETA 10:00")
    }

    func testPercentOnlyLineStillWorks() {
        XCTAssertEqual(LMStudioManager.progressStatus(from: "Loading 47%", label: "Loading refinement model"),
                       "Loading refinement model — 47%")
    }

    func testNonProgressLineIsIgnored() {
        XCTAssertNil(LMStudioManager.progressStatus(from: "Resolving model qwen/qwen3-8b", label: "Downloading"))
        XCTAssertNil(LMStudioManager.progressStatus(from: "", label: "Downloading"))
    }

    func testStripsAnsiAndControlNoise() {
        let stripped = LMStudioManager.stripControlCharacters("\u{1B}[2K\u{1B}[1Ghello\u{1B}[?25h")
        XCTAssertEqual(stripped, "hello")
    }

    func testParsesRuntimeSelectName() {
        let out = "Download completed.\nSelect the runtime using:\n\n  lms runtime select mlx-llm-mac-arm64-apple-metal-advsimd@1.9.1\n"
        XCTAssertEqual(LMStudioManager.parseRuntimeSelectName(from: out),
                       "mlx-llm-mac-arm64-apple-metal-advsimd@1.9.1")
    }

    func testRuntimeSelectNameNilWhenAbsent() {
        XCTAssertNil(LMStudioManager.parseRuntimeSelectName(from: "Download completed. Nothing to select."))
    }
}
