# Loro

A Spanish-first macOS dictation app. Push-to-talk, on-device transcription, text inserted at the cursor.

## Install

**Requires:** macOS 14+ on Apple Silicon (M1 or newer).

1. Download **Loro-macos-arm64.dmg** from [Releases](https://github.com/brunozapico/loro/releases).
2. Open the disk image and drag **Loro** to **Applications**.
3. Open **Loro** from Applications or Spotlight. In **Settings → Permissions**, allow Loro to use the microphone and Accessibility.

Loro appears in the Dock and the menu bar. Close its settings window to keep dictating, or press **⌘Q** while Loro is active to quit completely. Open it again whenever you need it; no terminal is required.

Builds currently use ad-hoc signing, without Apple notarization. For a downloaded build, macOS may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. Do this only for a download you trust. Grant permissions to **Loro**, not to Terminal. Existing preferences and downloaded models are reused; permissions may need to be granted again for the app.

An existing Loro launch-at-login agent is migrated when the installed app first opens. It opens the app through Launch Services and does not restart it after ⌘Q. To manage login manually, add Loro in **System Settings → General → Login Items**, or use the optional CLI commands below.

The optional terminal installer also installs the application:

```sh
curl -fsSL https://raw.githubusercontent.com/brunozapico/loro/main/scripts/install.sh | bash
```

## How to use

1. **Open Loro from Applications.** Settings appear immediately while the model loads. On first launch, the model needs to download; the menu bar shows when Loro is ready.
2. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
4. **The transcript types itself in at the cursor** when you release. Processing time depends on the model and recording length.

That's it. There is no record button and no "send" — your global shortcut is the dictation interface.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," `loro doctor` will tell you how to flip it back to plain `fn`.

## Settings

Open the bird icon in the menu bar and choose **Settings…**. Preferences persist across launches; all changes except the transcription model apply immediately.

- **Global shortcut** — click the shortcut field and press any key or modifier combination. `fn` remains the default.
- **Activation** — choose **Push to Talk** (hold to record) or **Toggle** (press once to start, again to stop).
- **Automatic silence detection** — in Toggle mode, stop and transcribe after a configurable period without speech (five seconds by default).
- **Recording overlay** — show or hide the waveform pill.
- **Clipboard** — optionally copy every final transcript. If cursor injection cannot start, Loro copies it anyway so it remains available with `⌘V`.
- **Transcription model** — choose a Spanish + English multilingual model or retain an English-only model. The choice persists across launches.
- **Custom dictionary** — replace spoken words or phrases with exact text, such as `te paso mi mail` → `name@example.com`.
- **Local correction** — optionally improve punctuation, grammar, capitalization, proper names, and accidental repetitions with Apple Foundation Models.
- **Permissions** — see microphone and Accessibility status and jump directly to the relevant System Settings pane.

The recommended model is Whisper Large v3 626 MB, optimized for maximum multilingual accuracy. Language is detected for every dictation, so Spanish and English utterances can alternate without changing a setting; occasional English terms inside Spanish speech remain supported. Model changes take effect after restarting Loro. `--model` remains a session-only override.

Local correction requires macOS 26, an eligible Apple Silicon Mac, and Apple Intelligence enabled. It is optional and always falls back to the original Whisper transcript if the model is unavailable, Low Power Mode is active, an error occurs, or the four-second timeout is reached.

## Privacy

- Audio exists only in memory while recording and transcription are in progress. Loro never writes it to disk.
- Transcripts are injected directly at the cursor. Loro does not log or persist them.
- Automatic clipboard copying is enabled by default and can be disabled in Settings. Loro writes only the latest result to the macOS pasteboard and keeps no separate clipboard history.
- There is no transcript history, telemetry, or cloud transcription.
- Apple Foundation Models correction runs on-device with no cloud API or network request. A fresh model session is used for each dictation.
- Correction context exists only in RAM: at most six recent fragments (about 800–1000 tokens), expiring after three minutes and resetting when the foreground app changes. **New Context**, disabling correction, quitting, or `^C` clears it.
- Custom replacement rules are stored locally in app preferences because they are user configuration; they are never sent anywhere.
- Diagnostic events contain only failure categories, never audio or transcript content. They are available in macOS Console under `com.brunozapico.loro`.
- Installing or uninstalling the LaunchAgent removes log and WAV artifacts left by legacy versions.

Loro connects to Hugging Face only to download the selected WhisperKit model. Once downloaded, transcription runs locally through CoreML.

## Optional CLI

The app includes its executable at `/Applications/Loro.app/Contents/MacOS/loro`. The separate CLI archive remains available for development; extract its resource bundles alongside the executable.

```sh
/Applications/Loro.app/Contents/MacOS/loro install --launch-at-login
/Applications/Loro.app/Contents/MacOS/loro install --uninstall
/Applications/Loro.app/Contents/MacOS/loro models list
/Applications/Loro.app/Contents/MacOS/loro models download whisper-small
```

The old `/usr/local/bin/loro` executable is no longer needed. Open the app to use the updated version. Direct CLI runs remain attached to their terminal session.

## Recovery and limits

- Input-device changes finish the current recording; the next recording uses a fresh audio engine.
- A recording is capped at five minutes (16 kHz mono in memory).
- Correction falls back to the original transcript after four seconds, even if the framework does not promptly cancel.
- Transcription returns an error after two minutes. A stalled inference is not duplicated; if the framework never recovers, quit and reopen Loro.
- Startup model loading has a five-minute deadline and leaves Settings and Quit responsive. If the download needs longer, reopen to retry.
- Two current-version instances cannot record simultaneously. Quit an old CLI version before upgrading.

See [the stability investigation](docs/stability.md) for evidence, changes and validation limits.

## Stack

- **Swift** — SwiftPM executable packaged as a macOS application
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **Apple Foundation Models** — optional on-device transcript correction on macOS 26+
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSPasteboard** — optional last-transcript clipboard delivery
- **NSWindow** (borderless, click-through) — recording-indicator pill

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

Use Swift 6+ with the macOS 26 SDK (full Xcode or current Command Line Tools). Deployment remains macOS 14+; Foundation Models is used only on macOS 26+.

```sh
scripts/test.sh
scripts/build-app.sh 0.2.0
open dist/Loro-macos-arm64.dmg
```

The build creates `Loro.app`, a drag-to-Applications DMG, a ZIP and checksums in `dist/`. CI runs the tests and creates installer artifacts on every push to main; version tags publish them in Releases. Set `CODESIGN_IDENTITY` to a Developer ID identity for signing; notarization is a separate distribution step.
