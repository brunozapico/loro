# parrot

A minimal macOS dictation daemon. Push-to-talk, on-device transcription, text inserted at the cursor.

## Install

```sh
curl -fsSL https://digimata.github.io/parrot/install.sh | sh
parrot setup                       # grants microphone + accessibility
parrot install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/parrot`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

## How to use

1. **Run it.** Either `parrot install --launch-at-login` (daemonized, runs forever, lives in the menu bar), or `parrot` in any terminal tab.
2. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
4. **The transcript types itself in at the cursor** when you release. Usually within 200-300ms.

That's it. There is no record button and no "send" — your global shortcut is the dictation interface.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," `parrot doctor` will tell you how to flip it back to plain `fn`.

## Settings

Open the bird icon in the menu bar and choose **Settings…**. Changes apply immediately and persist across launches.

- **Global shortcut** — click the shortcut field and press any key or modifier combination. `fn` remains the default.
- **Activation** — choose **Push to Talk** (hold to record) or **Toggle** (press once to start, again to stop).
- **Recording overlay** — show or hide the waveform pill.
- **Selected model** — see the active model, identifier, languages, and download size.
- **Custom dictionary** — replace spoken words or phrases with exact text, such as `te paso mi mail` → `name@example.com`.
- **Permissions** — see microphone and Accessibility status and jump directly to the relevant System Settings pane.

The selected model remains controlled by `--model`; changing models from the GUI is not yet supported.

## Privacy

- Audio exists only in memory while recording and transcription are in progress. Parrot never writes it to disk.
- Transcripts are injected directly at the cursor. Parrot does not log, store, or retain them.
- There is no transcript history, clipboard history, telemetry, or cloud transcription.
- Custom replacement rules are stored locally in app preferences because they are user configuration; they are never sent anywhere.
- When running as a LaunchAgent, stdout and stderr are discarded through `/dev/null`.
- Installing or uninstalling the LaunchAgent removes legacy Parrot log and WAV files from `/tmp`.

Parrot connects to Hugging Face only to download the selected WhisperKit model. Once downloaded, transcription runs locally through CoreML.

## CLI

```sh
parrot                                 # run in the foreground (^C to quit)
parrot setup                           # one-time permission setup
parrot install --launch-at-login       # register a LaunchAgent (background daemon)
parrot install --uninstall             # remove the LaunchAgent
parrot doctor                          # check permissions + fn key setting
parrot models list                     # list available models
parrot models download <id>            # pre-download a model
parrot --model whisper-large-v3-turbo  # bigger, multilingual, slower first-run
parrot --no-overlay                    # override the overlay setting for this run
```

## Stack

- **Swift** — single SPM executable target
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

```sh
swift build -c release
.build/release/parrot --help
```
