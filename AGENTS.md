# AGENTS.md — setup instructions for AI agents

This file tells any AI agent (Cursor, Claude Code, Windsurf, …) how to set up and build Šapat
on a user's Mac. **If a user hands you a link to this repo and asks you to "install / set up
Šapat", follow the _Install_ section below — it's fully scripted.**

Šapat is a macOS 14+ menu-bar app: record/​import Serbian speech → on-device WhisperKit
transcription → a local **ThoughtPipeline** (clean → extract → retrieve → reason → critique →
synthesize) run by an **in-process MLX** model → the artifact for the selected Output Mode.
**No external services, no other apps required.** Distributed via GitHub Releases, ad-hoc
signed, with a fail-closed (ed25519) in-app updater.

For the user-facing feature overview, see [README.md](README.md) — this file stays focused on
setup, build, and the agent/maintainer specifics.

## Install (do this when asked to set up the app)

The installer cleans up any prior install, downloads the latest release, verifies its
checksum, strips the Gatekeeper quarantine (the app is ad-hoc signed, not notarized), installs
to `/Applications`, and launches:

```sh
git clone https://github.com/pavstev/sapat.git
cd sapat
./scripts/install.sh
```

No clone needed:

```sh
curl -fsSL https://raw.githubusercontent.com/pavstev/sapat/main/scripts/install.sh | bash
```

Then tell the user:
- On first launch macOS asks for **microphone** access — they must **Allow** it.
- First launch downloads the **speech model** (WhisperKit) and the **reasoner model** (MLX),
  cached **outside** the app bundle in `~/Library/Application Support/Sapat/Models`, so updates
  never re-download them. The popover shows real download progress.
- The app lives in the **menu bar** (a **Ш** glyph), with **no Dock icon**.
- Default hotkey is **⌥⇧Space** (start/stop recording from anywhere).
- **No other apps are required** — inference runs in-process. (LM Studio is an optional opt-in
  backend only.)

Requirements: macOS 14+ (Apple Silicon), `curl` + `python3` (preinstalled on macOS).

## Clean slate (precondition)

```sh
./scripts/cleanup.sh            # quit + uninstall the app, clear build artifacts
./scripts/cleanup.sh --purge    # ALSO delete saved history, the memory index, and downloaded models
```

## Build from source

```sh
./bundle.sh && open Sapat.app    # currently: swift build + assemble & ad-hoc sign
```

Today `bundle.sh` uses `swift build` (Command Line Tools), which compiles the **engine-agnostic
layers** (Inference, Pipeline, Memory, Updater) — the `Inference` default then resolves to the
optional LM Studio backend, since the in-process MLX engine is staged behind
`#if canImport(MLXLLM)`.

The **self-contained default (MLX)** requires the **full Xcode** toolchain because MLX Swift's
Metal kernels (`default.metallib`) are compiled by Xcode's Metal compiler and are not shipped
precompiled — a plain `swift build` produces a binary that crashes on the first GPU op. Turning
it on is the one-time activation below; after that, `bundle.sh` drives `xcodebuild`.

## Conventions & gotchas (if you edit the code)

- **Build with `xcodebuild`** (full Xcode). The old "no full Xcode / `swift build` only" rule
  is **dropped** — it blocked MLX Swift (Metal shaders) and Apple Foundation Models
  (`@Generable`). `swift build` still compiles the engine-agnostic layers (Inference, Pipeline,
  Memory, Updater) under the CLT for fast iteration; the MLX engine is guarded by
  `#if canImport(MLXLLM)` so the CLT build stays green. (SwiftData/`#Preview`/Swift Testing are
  now technically available too, but are **not** adopted — keep diffs focused; tests stay XCTest.)
- **Swift 6 strict concurrency is on.** Preserve isolation: `RecorderViewModel`/`HistoryStore`
  are `@MainActor @Observable`; the heavy work (`WhisperEngine`, `Refiner`, `ThoughtPipeline`,
  `MemoryStore`, `MLXInference`) lives in **actors** so it never blocks the main actor. Marshal
  back with `Task { @MainActor in … }`.
- **Inference is engine-agnostic.** Everything refines through the `Inference` protocol +
  `Refiner`/`ThoughtPipeline`; selecting a backend never changes a caller. Default is in-process
  **MLX** (`MLXInference`); **LM Studio** (`LMStudioInference`) is an opt-in; an optional cloud
  `AnthropicInference` is off by default. LM-Studio-specific bits (the `lms` CLI, `:1234`) are
  sealed inside `LMStudioInference`/`LMStudioManager`/`LMStudioClient`.
- **The whole-recording guarantee + no-fabrication contract are load-bearing.** `Refiner` (the
  Clean stage) splits long transcripts on sentence boundaries, refines each, and merges +
  de-dupes — the start is never truncated. Prompts work *only with what was said*;
  `OutputSanitizer` is a mechanical net on each reply. Don't regress these.
- **Models live outside the bundle** (`Brand.modelsDirectory()` →
  `~/Library/Application Support/Sapat/Models`) so the in-place updater never wipes them and a
  multi-GB model is fetched once. `ModelStore` does resumable, integrity-checked,
  never-re-downloaded fetches; MLX/WhisperKit caches are likewise external.
- **Updates are fail-closed.** `UpdateChecker` verifies a detached **ed25519** signature over
  the zip against the public key embedded in `ReleaseSignature.swift`; a missing/invalid
  signature **aborts** the install (SHA-256 is only a corruption pre-check). Releases are signed
  in CI from the `SAPAT_SIGNING_KEY` secret (`scripts/sign-release.swift`).
- **Hotkey is ⌥⇧Space** via Carbon `RegisterEventHotKey` — kept deliberately: it needs no
  Accessibility permission, unlike a `CGEvent` tap. Bridged to Swift concurrency with
  `MainActor.assumeIsolated`.
- Ad-hoc signed, non-sandboxed, local-only. Releases are tag-triggered: `git tag vX.Y.Z &&
  git push origin vX.Y.Z`. Always verify a change by building + launching (menu-bar agent, no
  Dock icon).

## Activating / validating the MLX engine (one-time, needs full Xcode)

The in-process MLX engine is staged behind `#if canImport(MLXLLM)`. To turn it on:

1. Install full Xcode (`xcodes install --latest`; `sudo xcode-select -s …`).
2. Add the package dependency in **`Package.swift`** and **`project.yml`**:
   `https://github.com/ml-explore/mlx-swift-lm` → products `MLXLLM`, `MLXLMCommon`.
3. `./bundle.sh` (now uses `xcodebuild`). `canImport(MLXLLM)` becomes true, so `MLXInference`
   compiles and becomes the default backend; verify `Sapat.app/Contents/.../mlx-swift_Cmlx.bundle/default.metallib`
   ships, and validate `MLXInference` against the pinned `mlx-swift-lm` API (the model-load /
   generate calls are the version-sensitive surface).
4. `xcodebuild test -scheme Sapat` — run the full suite (XCTest needs Xcode; it is unavailable
   to `swift test` under the Command Line Tools).

## Notarization (when a Developer ID is available)

Ad-hoc signing means the installer strips quarantine. For a notarized build: sign with a
"Developer ID Application" cert + hardened runtime (`--options runtime --timestamp`), then
`xcrun notarytool submit Sapat.zip --apple-id … --team-id … --password … --wait` and `xcrun
stapler staple Sapat.app`. Keep the in-app ed25519 check regardless — notarization is OS-level
trust; the embedded-key signature proves the bytes came from this release pipeline (fail-closed).

## Continuing on a new machine (or a fresh Claude)

1. **Prereqs:** macOS 14+ (Apple Silicon), **full Xcode** (for MLX) — `xcodes install --latest`;
   `xcodegen` (`brew install xcodegen`); `git`, `gh`.
2. **Identity:** `gh auth login` (GitHub **pavstev**), then `git config user.name pavstev &&
   git config user.email pavstev@users.noreply.github.com`.
3. `git clone https://github.com/pavstev/sapat.git && cd sapat`
4. Build + run: `./bundle.sh && open Sapat.app`.
5. Read **Conventions & gotchas** before editing. History is in the commit log; in-flight work
   is in GitHub issues/PRs.

Identity facts: bundle id `com.stevanpavlovic.Sapat`; no Apple Developer account (ad-hoc
signing). Names, paths, and the repo slug derive from `Sources/Brand.swift`.

## Project status & roadmap

- **Shipped (the re-architecture):**
  1. **Self-contained inference** — engine-agnostic `Inference` protocol; `Refiner` actor;
     `ModelStore` for self-managed external model downloads; LM Studio severed to an opt-in.
  2. **ThoughtPipeline + Output Modes** — staged clean/extract/reason/critique/synthesize; six
     data-driven modes; Polished English unchanged.
  3. **Semantic memory** — GRDB + FTS5 + on-device embeddings, RRF hybrid; retrieval wired into
     the pipeline; history indexed (JSON stays the record of truth, retry preserved).
  4. **Hardening** — fail-closed ed25519 updater (+ CI signing); quit-while-busy guard.
  5. **Docs/tests/release** — this rewrite; XCTest coverage for the pipeline, sanitizer, memory,
     and the updater's fail-closed verification.
- **Deferred backlog:** swap the reasoner to a larger local model via a setting; `sqlite-vec`
  ANN for memory at scale (v2); `NLContextualEmbedding` for Serbian semantic search (v2);
  notarization once a Developer ID exists.
- **Cut a release:** `git tag vX.Y.Z && git push origin vX.Y.Z` → CI builds, **signs**, and
  publishes the GitHub Release; the in-app updater and `scripts/install.sh` pick it up.
