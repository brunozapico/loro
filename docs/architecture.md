# Architecture

## Goals

1. **Menu bar utility.** Single CLI-built binary with no dock icon and a small native settings window.
2. **Configurable activation.** Use any global shortcut in Push-to-Talk or Toggle mode.
3. **Minimal recording feedback.** A small floating pill at the bottom of the screen while recording, so the user knows the mic is hot. Click-through, borderless, hidden when idle.
4. **On-device and ephemeral.** No network calls for transcription. Audio never leaves the machine and is never written to disk.
5. **Pluggable models.** Whisper out of the box; Parakeet (or future engines) via a JSON-driven registry.
6. **Native and lean.** One Swift Package executable target. No sidecar processes. No HTTP servers.

## Non-goals

- Cross-platform (macOS only)
- Dock icon or a traditional main application window
- Cloud transcription providers
- AI post-processing, summarization, agents
- Speaker diarization, meeting recording, semantic search

## Why Swift

- **CoreML / ANE access.** WhisperKit and FluidAudio are Swift-native and run inference on the Apple Neural Engine — lower power, lower latency than CPU/GPU paths in Rust.
- **No FFI for platform APIs.** `AVAudioEngine`, `CGEventTap`, `CGEvent`, `AXIsProcessTrusted`, `NSWindow` — all first-party, no bindings to maintain.
- **Permissions plumbing** (microphone, accessibility) is dramatically smoother in a Swift binary than via Rust crates.
- **AppKit overlay for free.** The recording indicator (see below) is a borderless `NSWindow` — trivial in Swift, awkward in Rust.

The binary is a Swift Package executable — `swift build`, `swift run`, ship a single binary. Even with the menu bar item, settings window, and overlay, there is no `.app` bundle or dock icon.

## High-level shape

```
$ parrot
                                    ┌──────────────────┐
                                    │   ParrotCLI      │
                                    │  (Parrot.swift)  │
                                    └────────┬─────────┘
                                             │ wires modules, runs RunLoop
                                             ▼
┌──────────────────┐  hotkey down   ┌──────────────────┐
│   HotkeyMonitor  │ ─────────────▶ │  AudioCapture    │
│  (CGEventTap)    │  hotkey up     │ (AVAudioEngine)  │
└──────────────────┘ ◀───────────── └────────┬─────────┘
                                             │ [Float] PCM
                                             ▼
                                    ┌──────────────────┐
                                    │   Transcriber    │
                                    │   (protocol)     │
                                    │  ┌────────────┐  │
                                    │  │ WhisperKit │  │
                                    │  └────────────┘  │
                                    │  ┌────────────┐  │
                                    │  │  Parakeet  │  │
                                    │  └────────────┘  │
                                    └────────┬─────────┘
                                             │ String
                                             ▼
                                    ┌──────────────────┐
                                    │  TextInjector    │
                                    │   (CGEvent)      │
                                    └──────────────────┘
```

## Modules

### `Parrot.swift` (ParrotCLI)

Argument parsing (via `swift-argument-parser`), settings loading, and module wiring. Calls `NSApplication.shared.setActivationPolicy(.accessory)` so the process has no dock icon, then runs `NSApp.run()` to drive the menu bar item, settings window, overlay, event tap, and audio engine. Exits cleanly on SIGINT. The daemon does not log recordings, transcripts, keyboard events, or operational status.

Subcommands:
- `parrot` (default) — run the daemon
- `parrot models list` — show registered models, mark which are downloaded
- `parrot models download <id>` — pre-fetch a model
- `parrot doctor` — check microphone and accessibility permissions, print remediation steps

### `HotkeyMonitor`

Global shortcut via `CGEventTap` (requires Accessibility permission). Default: **Fn**, with support for arbitrary key and modifier combinations. Modifier-only shortcuts use `flagsChanged`; key-based shortcuts use `keyDown` / `keyUp`. Matching events are consumed so the shortcut does not also trigger the foreground application. Changes from the settings window apply without restarting the event tap.

`DictationController` interprets the emitted `.pressed` / `.released` edges:

- **Push to Talk** — press starts capture, release stops and transcribes.
- **Toggle** — each press alternates between starting and stopping capture; release is ignored.

**Fn key caveat:** macOS by default maps the Fn (🌐) key to "Show Emoji & Symbols" or "Start Dictation" depending on the user's setting in System Settings → Keyboard → Press 🌐 key to. The CGEventTap sees the keypress regardless, but the system action also fires. `parrot doctor` will detect this setting and instruct the user to change it to "Do Nothing" so Fn becomes a clean modifier.

### `AudioCapture`

`AVAudioEngine` tap on the input node. Streams 16 kHz mono `Float32` buffers in memory while recording is active. When the selected activation mode stops recording, it hands the full buffer to the active `Transcriber`.

### `Transcriber` (protocol)

```swift
protocol Transcriber {
    func transcribe(_ audio: [Float]) async throws -> String
    var modelID: String { get }
}
```

Concrete implementations:

- `WhisperKitTranscriber` — wraps the `WhisperKit` package. CoreML, ANE-accelerated. Multilingual models explicitly enable per-dictation language detection with `DecodingOptions.detectLanguage`; English-only models pin `language` to `en`. The task is always `.transcribe`, never translation.
- `ParakeetTranscriber` — wraps `FluidAudio` (or direct CoreML) for NVIDIA Parakeet TDT.

Adding an engine = one new file conforming to `Transcriber`.

### `TextInjector`

`CGEventCreateKeyboardEvent` + `CGEventKeyboardSetUnicodeString` — pastes the transcript at the current cursor position. Works in nearly every text field on macOS (some Electron apps and secure fields are flaky; platform constraint).

### `RecordingOverlay`

A single borderless `NSWindow` displayed at the bottom-center of the active screen while recording. It provides transient visual feedback while the menu bar and settings window provide the persistent controls.

Window configuration:
- `styleMask: .borderless`
- `backgroundColor: .clear`, `isOpaque: false`, `hasShadow: true`
- `level: .statusBar` (or `.floating`) — sits above all other windows
- `ignoresMouseEvents = true` — clicks pass through to whatever is underneath
- `collectionBehavior: [.canJoinAllSpaces, .stationary, .ignoresCycle]` — visible across Spaces, doesn't appear in window switcher

Content: a small SwiftUI view hosted via `NSHostingView`, showing a pulsing dot + "listening" text, optionally a live mic level meter fed from `AudioCapture`. Total footprint: ~120pt wide, ~40pt tall, positioned 60pt above the bottom of the screen.

States:
- **Hidden** — idle. No window on screen.
- **Recording** — shown on `.pressed`, mic level animated.
- **Transcribing** — brief spinner state between stopping a recording and text injection (usually <500 ms).
- **Hidden** — back to idle after injection.

This is the only reason the process needs an `NSApplication` run loop instead of a bare `CFRunLoop`.

### `ModelRegistry`

Source-backed model registry:

```swift
struct TranscriptionModel: Codable {
    let id: String              // "whisper-large-v3"
    let displayName: String
    let engine: Engine          // .whisperKit | .parakeet
    let sizeMB: Int
    let whisperKitID: String?
    let languages: [String]
    let languageMode: TranscriptionLanguageMode
    let recommended: Bool
}

enum Engine: String, Codable { case whisperKit, parakeet }
```

Backed by static values in `ModelRegistry.swift`, keeping the executable self-contained. Adding a model means appending an entry. Adding an engine requires a new `Transcriber` conformance and an `Engine` case.

The registry is the single source of truth for model identifiers, display names, sizes, languages, recommended flags, and what appears in the GUI and `parrot models list`. WhisperKit owns model download and caching.

### `SettingsStore` + `SettingsWindowController`

The menu bar's **Settings…** item opens a native tabbed SwiftUI interface hosted in an `NSWindow`. `SettingsStore` persists user configuration in the `com.digimata.parrot` `UserDefaults` suite:

- global shortcut key code, modifier mask, and display label
- activation mode (`pushToTalk` or `toggle`)
- whether to show the recording overlay
- selected default transcription model
- custom spoken-phrase replacement rules

Shortcut, activation, overlay, and replacement changes apply immediately. Model selection persists but applies on the next launch because the CoreML pipeline is loaded and warmed once at process startup. A `--model` value overrides the saved selection for that run without modifying it.

Replacement rules may contain personal values such as email addresses, so the UI explicitly identifies them as local preferences; they never enter logs or network requests. The `--no-overlay` CLI flag remains a session-level override and disables the GUI toggle for that run.

## Permissions

Two permissions are required and surfaced both through `parrot doctor` and the GUI's **Permissions** tab:

1. **Microphone** — standard `AVCaptureDevice` request, fires on first audio engine start.
2. **Accessibility** — required for `CGEventTap` (hotkey) and `CGEvent` posting (text injection). User toggles in System Settings → Privacy & Security → Accessibility, granting the *terminal* (or whatever launched parrot) permission, since the binary inherits its parent's TCC identity.

`PermissionManager` refreshes both states whenever the app becomes active. Missing permissions no longer prevent the menu bar and settings window from starting: Parrot opens the Permissions tab, shows a clear granted/missing state, and links directly to the matching System Settings pane. When Accessibility becomes available, the global shortcut monitor starts without requiring a process restart.

`parrot doctor` remains available for terminal-based diagnostics and prints actionable next steps.

### TCC quirk worth knowing

When you launch `parrot` from `Terminal.app`, accessibility permission is granted to *Terminal*, not parrot itself. This means:
- Switching terminals (Terminal → iTerm → Ghostty) requires re-granting permission.
- Running under `launchd` requires granting permission to whatever spawns it.

This is a macOS platform behavior, not a parrot bug. `parrot doctor` will identify the parent process and tell the user which app needs the permission.

## Models — what ships

Spanish-first registry:

| Engine | Model | Size | Notes |
|---|---|---|---|
| WhisperKit | `whisper-large-v3` | 626 MB | Recommended; maximum Spanish + English accuracy, automatic language detection |
| WhisperKit | `whisper-small` | 486 MB | Balanced multilingual option |
| WhisperKit | `whisper-base` | 147 MB | Lightweight multilingual option |
| WhisperKit | `whisper-base.en` | 145 MB | Lightweight English-only fallback |
| WhisperKit | `whisper-small.en` | 486 MB | Higher-quality English-only fallback |

Models are not bundled. WhisperKit downloads and caches them on first selection or through `parrot models download`. The recommended 626 MB Large v3 variant follows WhisperKit's own recommendation for maximum multilingual accuracy. The English-only entries remain available, but automatic Spanish/English switching requires one of the multilingual entries.

## Data flow, end-to-end

1. User runs `parrot` in a terminal.
2. `ParrotCLI` loads persisted settings and instantiates modules.
3. Sets `.accessory` activation policy and enters `NSApp.run()`. Missing permissions are presented in the settings window instead of terminating the process.
4. User activates the configured shortcut.
5. `HotkeyMonitor` fires `.pressed`. According to the selected mode, `DictationController` starts recording immediately or toggles the current recording state.
6. `AudioCapture` starts the AVAudioEngine tap. Buffers fill. Overlay animates mic level.
7. Push-to-Talk stops on release; Toggle stops on the next press.
8. Overlay switches to spinner. Status: `transcribing`.
9. `AudioCapture` stops, hands buffer to active `Transcriber`.
10. `Transcriber` detects the utterance language for multilingual models, runs CoreML inference in transcription mode, and returns text in the spoken language.
11. `TextReplacementEngine` applies the configured local phrase substitutions in memory.
12. `TextInjector` posts the resulting string at the cursor.
13. Overlay hides. Status: `listening`. Loop.
14. User hits `^C`. Process exits cleanly.

End-to-end latency target: <500 ms after recording stops for utterances under 10 seconds, on Apple Silicon.

## What we are deliberately NOT building

- No streaming partial transcripts in v1. Press, speak, release, get full text.
- No VAD-based hands-free mode. Push-to-talk is more reliable and uses zero idle CPU.
- No history, transcript log, audio dump, telemetry, or clipboard manager. Output goes to the cursor and that's it.
- LaunchAgent output is discarded through `/dev/null`; no persistent daemon log is created.
- No model-level custom vocabulary, prompting, or AI post-processing. User-defined replacements are deterministic local string substitutions.
- No transcript editor, history browser, or general preferences application. UI remains limited to the menu bar, focused settings window, and recording overlay.

These are deliberate cuts. Each can be revisited if real usage demands it.

## Project layout

Organized by feature area. These are folders within a single SPM executable target — Swift sees them as one module, but the directory grouping keeps related code together. If a group later earns its keep as a reusable library (e.g. `Transcription` consumed by another tool), it can be promoted to its own SPM target with no rewriting.

```
parrot/
  Package.swift                 # SPM, single executable target
  Sources/parrot/
    Parrot.swift                # entry point, argument parsing, NSApp.run()
    DictationController.swift   # push-to-talk/toggle recording lifecycle
    Doctor.swift
    Install.swift
    Setup.swift

    Transcription/              # the inference layer
      Transcriber.swift         # protocol
      WhisperKitTranscriber.swift

    Models/
      AppSettings.swift         # persisted shortcut, mode, model, overlay, and replacements
      ModelRegistry.swift
      TextReplacement.swift     # custom replacement model + in-memory engine
      TranscriptionModel.swift  # Codable types

    Permissions/
      PermissionManager.swift   # live TCC status + System Settings links

    Audio/
      AudioCapture.swift        # AVAudioEngine tap + ring buffer

    Input/
      HotkeyMonitor.swift       # CGEventTap
      TextInjector.swift        # CGEvent posting

    UI/
      MenuBarController.swift
      RecordingOverlay.swift    # borderless NSWindow + SwiftUI pill
      SettingsWindowController.swift

  docs/
    architecture.md
  README.md
```

Build: `swift build -c release`. Resulting binary at `.build/release/parrot`. Install: copy to `~/.local/bin/` or `/usr/local/bin/`.

### On Swift "modules"

Swift's module unit is the **SPM target** (one target = one module = one `import` namespace). For parrot v1 we use a single executable target with the folder structure above; everything is in the same module so no `import` statements between files. If we ever want enforced boundaries (e.g. `Transcription` and `UI` shouldn't reach into `Audio` internals), we promote folders to separate targets in `Package.swift` — a structural change, not a semantic one.

## Open questions

- **Parakeet via FluidAudio vs. direct CoreML?** FluidAudio is faster to integrate but adds a dependency. Decide once we benchmark both.
- **Hotkey conflicts.** Right-Option is unused on most keyboards but some users remap it. Print a clear error if `CGEventTap` registration fails.
- **First-run model download.** Add richer progress feedback for the recommended 626 MB model without persisting operational logs.
- **Code signing.** A self-built unsigned binary works fine locally but accessibility permission persistence is more reliable for signed binaries. Decide if we sign for personal distribution.
