import Foundation

/// Makes LM Studio mandatory by driving its `lms` CLI: locate the tool, start the local
/// server, and make sure the configured model is downloaded and loaded — then it's reused,
/// never re-fetched. When it genuinely can't be made ready, `ensureReady` throws and the
/// caller shows an actionable error (no silent fallback to the inferior Whisper path).
///
/// The download is resume-and-retry: `lms get` reports real progress and resumes a partial
/// `.part`, but its HuggingFace transfer can time out near the end — so we retry it (each
/// attempt resumes) until the model is actually present, rather than re-pulling from zero
/// or giving up. Progress is streamed out as ready-to-display strings.
struct LMStudioManager {
    /// Context window to request when we load the model ourselves — generous headroom so
    /// most recordings refine in a single pass. (The client still chunks if a transcript
    /// exceeds whatever is actually loaded, e.g. a smaller manual load.)
    var preferredContextLength = 8192
    /// Auto-unload the model after this long idle, so we don't hold ~6 GB forever.
    var modelIdleTTLSeconds = 3600
    /// `lms get` can stall and exit near the end; each retry resumes the `.part`.
    private static let maxDownloadAttempts = 10

    /// Locates the `lms` CLI. A Finder-launched app inherits a minimal PATH that excludes
    /// `~/.lmstudio/bin` (where the installer puts it), so we probe explicit locations.
    static func locateCLI(
        home: String = NSHomeDirectory(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> String? {
        let candidates = [
            "\(home)/.lmstudio/bin/lms",
            "\(home)/.cache/lm-studio/bin/lms",
            "/opt/homebrew/bin/lms",
            "/usr/local/bin/lms",
        ]
        return candidates.first(where: isExecutable)
    }

    /// Ensures `modelKey` is loaded and serving: starts the server if needed, downloads the
    /// model if (and only if) it's genuinely absent, then loads it. Idempotent and cheap
    /// when already loaded or downloaded. `onStatus` receives display-ready progress strings.
    func ensureReady(
        modelKey: String,
        client: LMStudioClient,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws {
        if await client.presence(of: modelKey) == .loaded { return }

        guard let cli = Self.locateCLI() else { throw LMStudioError.cliNotFound }

        if await client.isServerReachable() == false {
            onStatus("Starting LM Studio…")
            try await Self.run(cli, ["server", "start"], timeout: 30)
            await Self.waitUntil(timeout: 20) { await client.isServerReachable() }
        }

        // Resolve presence robustly — a transient query failure must NOT be read as "absent"
        // and trigger a needless multi-GB download.
        switch await stablePresence(of: modelKey, client: client) {
        case .loaded:
            return
        case .downloadedNotLoaded:
            try await loadModel(cli: cli, modelKey: modelKey, onStatus: onStatus)
        case .absent:
            try await downloadModel(cli: cli, modelKey: modelKey, client: client, onStatus: onStatus)
            try await loadModel(cli: cli, modelKey: modelKey, onStatus: onStatus)
        case .serverUnreachable:
            throw LMStudioError.notRunning
        }

        await Self.waitUntil(timeout: 60) { await client.presence(of: modelKey) == .loaded }
        guard await client.presence(of: modelKey) == .loaded else {
            throw LMStudioError.setupFailed("LM Studio couldn't load \(modelKey). Open LM Studio and load it manually, then Retry.")
        }
    }

    /// Presence, retried a few times so a momentary `/api/v0/models` hiccup (common while the
    /// server is busy downloading) doesn't masquerade as `.absent`.
    private func stablePresence(of modelKey: String, client: LMStudioClient) async -> LMStudioClient.ModelPresence {
        var last: LMStudioClient.ModelPresence = .serverUnreachable
        for attempt in 0..<3 {
            last = await client.presence(of: modelKey)
            if last != .serverUnreachable { return last }
            if attempt < 2 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        return last
    }

    // MARK: - Download (resume + retry to completion)

    private func downloadModel(
        cli: String,
        modelKey: String,
        client: LMStudioClient,
        onStatus: @escaping @Sendable (String) -> Void
    ) async throws {
        var attempt = 0
        while true {
            // Stop the moment it's actually present — covers "finished on a prior attempt"
            // and is the real fix for re-downloading every message.
            if await client.presence(of: modelKey) != .absent { return }
            attempt += 1
            onStatus(attempt == 1 ? "Preparing to download the refinement model…"
                                  : "Resuming download (attempt \(attempt))…")
            do {
                try await Self.runStreaming(cli, ["get", modelKey, "--mlx", "-y"], timeout: 7200) { line in
                    if let status = Self.progressStatus(from: line, label: "Downloading refinement model") {
                        onStatus(status)
                    }
                }
                return // `lms get` exited cleanly → the model is downloaded
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < Self.maxDownloadAttempts else {
                    throw LMStudioError.setupFailed(
                        "The model download keeps timing out (\(attempt) attempts). Open LM Studio to finish it, then Retry. (\(error.localizedDescription))")
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000) // brief backoff, then resume
            }
        }
    }

    private func loadModel(cli: String, modelKey: String, onStatus: @escaping @Sendable (String) -> Void) async throws {
        onStatus("Loading refinement model…")
        try await Self.runStreaming(cli, [
            "load", modelKey, "-y",
            "--context-length", String(preferredContextLength),
            "--ttl", String(modelIdleTTLSeconds),
        ], timeout: 600) { line in
            if let status = Self.progressStatus(from: line, label: "Loading refinement model") {
                onStatus(status)
            }
        }
    }

    // MARK: - Progress parsing (pure, unit-tested)

    /// Turns an `lms` progress line — e.g. `… 91.48% | 4.23 GB / 4.62 GB | 2.70 MB/s | ETA 02:26`
    /// (with spinner + ANSI noise) — into "Downloading refinement model — 91% · 4.23 GB / 4.62 GB · ETA 02:26".
    /// Returns nil for lines without a percentage.
    static func progressStatus(from raw: String, label: String) -> String? {
        guard raw.contains("%") else { return nil }
        let clean = stripControlCharacters(raw)
        guard let pct = captureGroups(#"([0-9]+(?:\.[0-9]+)?)\s*%"#, in: clean).flatMap({ Double($0[1]) }) else {
            return nil
        }
        var parts = ["\(label) — \(Int(pct.rounded()))%"]
        if let sizes = captureGroups(#"([0-9]+(?:\.[0-9]+)?\s*[KMGT]?B)\s*/\s*([0-9]+(?:\.[0-9]+)?\s*[KMGT]?B)"#, in: clean) {
            parts.append("\(normalizeSize(sizes[1])) / \(normalizeSize(sizes[2]))")
        }
        if let eta = captureGroups(#"ETA\s*([0-9:]+)"#, in: clean) {
            parts.append("ETA \(eta[1])")
        }
        return parts.joined(separator: " · ")
    }

    private static func normalizeSize(_ s: String) -> String {
        s.replacingOccurrences(of: "  ", with: " ").trimmingCharacters(in: .whitespaces)
    }

    static func stripControlCharacters(_ s: String) -> String {
        let noANSI = s.replacingOccurrences(
            of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
        let scalars = noANSI.unicodeScalars.filter { $0 == " " || $0 == "\t" || ($0.value >= 0x20 && $0.value != 0x7F) }
        return String(String.UnicodeScalarView(scalars))
    }

    private static func captureGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }

    // MARK: - Process plumbing (nonisolated: runs off the main actor)

    /// Runs `lms`, streaming each stdout/stderr line to `onLine` (for live progress) while
    /// keeping a tail for error reporting. Polls so the call stays cancellable and can time
    /// out; reading via a `readabilityHandler` means a chatty download can't deadlock a pipe.
    nonisolated private static func runStreaming(
        _ launchPath: String,
        _ args: [String],
        timeout: TimeInterval,
        onLine: @escaping @Sendable (String) -> Void
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.environment = augmentedEnvironment()

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let handle = pipe.fileHandleForReading
        let tail = TailBuffer()
        handle.readabilityHandler = { fileHandle in
            let data = fileHandle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            tail.append(text)
            for piece in text.split(whereSeparator: { $0 == "\r" || $0 == "\n" }) {
                let line = String(piece)
                if !line.isEmpty { onLine(line) }
            }
        }

        try process.run()
        defer { handle.readabilityHandler = nil }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
            if Date() > deadline {
                process.terminate(); process.waitUntilExit()
                throw LMStudioError.setupFailed("lms \(args.first ?? "command") timed out.")
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        guard process.terminationStatus == 0 else {
            throw LMStudioError.setupFailed("lms \(args.first ?? "command"): \(tail.lastMeaningfulLine())")
        }
    }

    /// Runs `lms` without progress streaming (server start). Output → temp file (no pipe to
    /// deadlock), read back only to explain a failure.
    nonisolated private static func run(_ launchPath: String, _ args: [String], timeout: TimeInterval) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.environment = augmentedEnvironment()

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sapat-lms-\(args.first ?? "cmd")-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: logURL)
        process.standardOutput = handle
        process.standardError = handle
        defer { try? FileManager.default.removeItem(at: logURL) }

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Task.isCancelled { process.terminate(); process.waitUntilExit(); throw CancellationError() }
            if Date() > deadline {
                process.terminate(); process.waitUntilExit()
                throw LMStudioError.setupFailed("lms \(args.first ?? "command") timed out.")
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        try? handle.close()
        guard process.terminationStatus == 0 else {
            let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LMStudioError.setupFailed(
                "lms \(args.first ?? "command") failed" + (detail.isEmpty ? " (exit \(process.terminationStatus))." : ": \(detail)"))
        }
    }

    nonisolated private static func augmentedEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        env["PATH"] = env["PATH"].map { "\($0):\(extra)" } ?? extra
        return env
    }

    /// Polls `condition` until true or the timeout elapses (best effort, no throw).
    nonisolated private static func waitUntil(timeout: TimeInterval, _ condition: @Sendable () async -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }
}

/// Thread-safe tail of a subprocess's output, for explaining a failure. The readability
/// handler runs on a background queue, so access is locked.
private final class TailBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ chunk: String) {
        lock.lock(); defer { lock.unlock() }
        text += chunk
        if text.count > 4000 { text = String(text.suffix(4000)) }
    }

    func lastMeaningfulLine() -> String {
        lock.lock(); defer { lock.unlock() }
        let clean = LMStudioManager.stripControlCharacters(text)
        let lines = clean.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? "the command failed"
    }
}
