# Glasnik

A native macOS menu bar app that turns Serbian speech into polished English.

Press a global shortcut (or click the menu bar mic), speak Serbian, and Glasnik
transcribes it on‑device with [WhisperKit](https://github.com/argmaxinc/argmax-oss-swift),
translates it to English, shows both, and copies the English to your clipboard.

It's **offline‑first**: everything runs on your Mac. A local
[Ollama](https://ollama.com) model is used *if available* to polish the translation,
but the app works fully without it.

> *Glasnik* (гласник) — Serbian for "messenger".

## How it works

```
record (16 kHz mono WAV)
   └─ WhisperKit  ──▶  Serbian transcript        (task: transcribe, language: sr)
        └─ translate:
             ├─ Ollama qwen2.5:3b  ──▶  polished English   (preferred, if running)
             └─ WhisperKit          ──▶  English baseline   (offline fallback, task: translate)
   └─ show Serbian + English, auto‑copy English to the clipboard
```

- Single, app‑level state machine: `preparing → idle → recording → transcribing → translating → done` (plus `error`).
- The model is prewarmed at launch and the microphone is requested up front, so the first record is instant.
- A no‑speech guard prevents Whisper from "hallucinating" text out of silence.

## Requirements

- macOS 14 (Sonoma) or later, Apple Silicon recommended.
- **Xcode 16+** (the SwiftUI/CoreML toolchain).
- **[XcodeGen](https://github.com/yonaskolb/XcodeGen)** to generate the project:
  ```sh
  brew install xcodegen
  ```
- *(Optional)* **Ollama** with the `qwen2.5:3b` model, for polished translations:
  ```sh
  brew install ollama        # or download from https://ollama.com
  ollama pull qwen2.5:3b
  ollama serve               # leave running
  ```

## Build & run

```sh
cd Glasnik
xcodegen generate           # writes Glasnik.xcodeproj from project.yml
open Glasnik.xcodeproj       # then ⌘R in Xcode
```

On first launch Glasnik downloads the `openai_whisper-small` model (~250 MB) from
Hugging Face — the popover shows **"Preparing model…"** until it's ready. macOS will
also prompt once for microphone access.

The app has no Dock icon (`LSUIElement`); look for the **mic icon in the menu bar**.

## Usage

- **Click** the menu bar mic to open the popover, then click the big button to start/stop.
- **Global shortcut** (default **⌥⌘G**) starts/stops recording from any app and opens
  the popover for feedback. Rebind it in the popover footer or in Settings (⌘,).
- The mic icon turns **red** while recording. On completion the English is shown and
  **auto‑copied** to the clipboard (you'll see a "Copied ✓" confirmation).

## Translation quality

When Ollama is running, `qwen2.5:3b` translates the Serbian source directly into clean,
grammatical English. When it isn't, Glasnik falls back to Whisper's own translate task
— functional but blunter — and shows a non‑blocking hint with the command to start or
pull the model. Whisper's offline translation quality scales with model size; bump
`whisperModel` in `Sources/RecorderViewModel.swift` to `openai_whisper-large-v3`
(~1.5 GB) if you want better offline results at the cost of a larger download and more
latency.

## Distribution

This is set up for personal, local use: **ad‑hoc signed** ("Sign to Run Locally"),
**non‑sandboxed**, no notarization. The microphone prompt works via TCC + the usage
string in `Info.plist`. To share it with others you'd need a Developer ID identity and
a notarization step — not configured here.

## Project layout

| File | Responsibility |
| --- | --- |
| `project.yml` | XcodeGen project definition (target, packages, signing, Info.plist) |
| `Info.plist` | `LSUIElement`, `NSMicrophoneUsageDescription`, bundle metadata |
| `Sources/GlasnikApp.swift` | `@main`; app delegate adaptor + Settings scene |
| `Sources/AppDelegate.swift` | Status item, popover, global hotkey, status‑icon updates |
| `Sources/RecorderViewModel.swift` | `@Observable @MainActor` — all state and logic |
| `Sources/WhisperEngine.swift` | WhisperKit wrapper (transcribe + translate passes) |
| `Sources/OllamaClient.swift` | Local Ollama `/api/generate` client + typed errors |
| `Sources/PopoverView.swift` | SwiftUI popover (record button, transcript, status, hints) |
| `Sources/SettingsView.swift` | Preferences window with the shortcut recorder |
| `Sources/AppState.swift` | State machine + error/hint/action models |
| `Sources/Shortcuts.swift` | Global shortcut name + default (⌥⌘G) |

## Notes & limitations

- First run blocks on the model download; subsequent launches load from cache.
- The offline (Whisper‑small) translation is rougher than Ollama's polish.
- Ad‑hoc re‑signing on rebuilds can occasionally re‑prompt for microphone access.
- Bundle id: `com.stevanpavlovic.Glasnik`.

## Dependencies

- [argmax-oss-swift / WhisperKit](https://github.com/argmaxinc/argmax-oss-swift) — on‑device speech (pinned to 1.0.0)
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) — global hotkey
- [Ollama](https://ollama.com) + `qwen2.5:3b` — optional translation polish
