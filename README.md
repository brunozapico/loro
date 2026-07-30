# Loro

A Spanish-first macOS dictation app. Push-to-talk, on-device transcription, text inserted at the cursor.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/brunozapico/parrot/master/scripts/install.sh | sh
loro setup                       # grants microphone + accessibility
loro install --launch-at-login   # optional — runs in the background on login
```

**Requires:** macOS 14+ on Apple Silicon (M1 or newer). Transcription runs on the Apple Neural Engine via CoreML — so the installer refuses to run on Intel.

The installer drops the binary in `/usr/local/bin/loro`. Builds are unsigned for now, so the installer strips the quarantine xattr — once you've inspected the script you'll see exactly what it does.

Preferences and launch-at-login configuration from previous versions migrate automatically.

## How to use

1. **Run it.** Either `loro install --launch-at-login` (daemonized, runs forever, lives in the menu bar), or `loro` in any terminal tab.
2. **Click into the text field you want to dictate into** — Messages, the address bar, a Slack thread, anywhere a cursor blinks.
3. **Hold the `fn` key, speak, release.** A small pill appears at the bottom of the screen while the mic is hot.
4. **The transcript types itself in at the cursor** when you release. Usually within 200-300ms.

That's it. There is no record button and no "send" — your global shortcut is the dictation interface.

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If yours is set to "Change input source" or "Show emoji & symbols," `loro doctor` will tell you how to flip it back to plain `fn`.

## Settings

Open the bird icon in the menu bar and choose **Settings…**. Preferences persist across launches; all changes except the transcription model apply immediately.

- **Global shortcut** — click the shortcut field and press any key or modifier combination. `fn` remains the default.
- **Activation** — choose **Push to Talk** (hold to record) or **Toggle** (press once to start, again to stop).
- **Recording overlay** — show or hide the waveform pill.
- **Transcription model** — choose a Spanish + English multilingual model or retain an English-only model. The choice persists across launches.
- **Custom dictionary** — replace spoken words or phrases with exact text, such as `te paso mi mail` → `name@example.com`.
- **Local correction** — optionally improve punctuation, grammar, capitalization, proper names, and accidental repetitions with Apple Foundation Models.
- **Permissions** — see microphone and Accessibility status and jump directly to the relevant System Settings pane.

The recommended model is Whisper Large v3 626 MB, optimized for maximum multilingual accuracy. Language is detected for every dictation, so Spanish and English utterances can alternate without changing a setting; occasional English terms inside Spanish speech remain supported. Model changes take effect after restarting Loro. `--model` remains a session-only override.

Local correction requires macOS 26, an eligible Apple Silicon Mac, and Apple Intelligence enabled. It is optional and always falls back to the original Whisper transcript if the model is unavailable, Low Power Mode is active, an error occurs, or the four-second timeout is reached.

## Privacy

- Audio exists only in memory while recording and transcription are in progress. Loro never writes it to disk.
- Transcripts are injected directly at the cursor. Loro does not log or persist them.
- There is no transcript history, clipboard history, telemetry, or cloud transcription.
- Apple Foundation Models correction runs on-device with no cloud API or network request. A fresh model session is used for each dictation.
- Correction context exists only in RAM: at most six recent fragments (about 800–1000 tokens), expiring after three minutes and resetting when the foreground app changes. **New Context**, disabling correction, quitting, or `^C` clears it.
- Custom replacement rules are stored locally in app preferences because they are user configuration; they are never sent anywhere.
- When running as a LaunchAgent, stdout and stderr are discarded through `/dev/null`.
- Installing or uninstalling the LaunchAgent removes log and WAV artifacts left by legacy versions.

Loro connects to Hugging Face only to download the selected WhisperKit model. Once downloaded, transcription runs locally through CoreML.

## CLI

```sh
loro                                 # run in the foreground (^C to quit)
loro setup                           # one-time permission setup
loro install --launch-at-login       # register a LaunchAgent (background daemon)
loro install --uninstall             # remove the LaunchAgent
loro doctor                          # check permissions + fn key setting
loro models list                     # list available models
loro models download <id>            # pre-download a model
loro --model whisper-small           # lighter multilingual model for this run
loro --no-overlay                    # override the overlay setting for this run
```

## Stack

- **Swift** — single SPM executable target
- **WhisperKit** — Whisper inference via CoreML, ANE-accelerated
- **Apple Foundation Models** — optional on-device transcript correction on macOS 26+
- **AVAudioEngine** — mic capture
- **CGEventTap** — global hotkey
- **CGEvent** — text injection at cursor
- **NSWindow** (borderless, click-through) — recording-indicator pill

See [docs/architecture.md](docs/architecture.md) for design notes.

## Build from source

```sh
swift build -c release
.build/release/loro --help
```
