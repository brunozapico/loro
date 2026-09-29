# Loro

A Spanish-first macOS dictation app. Hold a shortcut, speak, and let the transcript type itself at the cursor. Runs on your Mac, lives in the Dock and menu bar, and opens like any other app.

## Install

**Requires:** macOS 14+ on Apple Silicon (M1 or newer).

1. **Download the installer.** Get [Loro-macos-arm64.dmg](https://github.com/brunozapico/loro/releases/latest/download/Loro-macos-arm64.dmg) from the [latest release](https://github.com/brunozapico/loro/releases/latest).
2. **Move Loro to Applications.** Open the DMG, drag **Loro** onto **Applications**, then eject the disk image.
3. **Open Loro.** Find it in Applications or search for it with Spotlight. No terminal command is needed.
4. **Grant permissions.** Open **Settings → Permissions** in Loro. Allow **Microphone** to record your voice and **Accessibility** to detect the shortcut and insert text. Enable **Loro** in System Settings when prompted.
5. **Let the model load.** The first launch downloads the selected model and prepares it for your Mac. This can take a few minutes. Settings remain available; the bird menu shows `idle` when the model is ready.

> **First launch:** local release builds use a persistent signing certificate and are not yet notarized by Apple. If macOS blocks a downloaded copy, try opening it once, then go to **System Settings → Privacy & Security → Open Anyway**. Only approve a download you trust.

The recommended model is about 626 MB. An internet connection is needed for the initial download; dictation runs locally once the model is ready.

### Updating from an older version

Quit Loro before replacing it in Applications. If you used the old terminal version, stop that process too — `⌘Q` in the new app does not close an older copy running elsewhere.

Preferences and downloaded models are reused. macOS may ask you to grant permissions again for **Loro**, even if the old executable or Terminal already had access. When migrating from an older ad-hoc build, check **Settings → Permissions** if the shortcut or microphone stops responding.

An existing Loro launch-at-login agent is migrated when the installed app first opens. The old `/usr/local/bin/loro` command is no longer needed; open the copy in Applications to use the update.

### Optional terminal installer

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

> **Note:** on most modern Macs the `fn` key is the bottom-left key. If it opens the emoji picker or changes the input source, set **System Settings → Keyboard → Press 🌐 key to → Do Nothing**, or choose another shortcut in Loro Settings.

## Opening and quitting

- **Close Settings** to leave Loro running. The bird stays in the menu bar and the dictation shortcut keeps working.
- **Open Settings again** by clicking Loro in the Dock, opening it from Applications, or choosing **Settings…** from the bird menu.
- **Quit completely** with **⌘Q** while Loro is active, or choose **Quit Loro** from its menu. Open it again whenever you want to dictate.
- **Start at login** by adding Loro in **System Settings → General → Login Items**, or use the optional CLI command below. Quitting Loro does not immediately restart it.

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

Local correction requires macOS 26, an eligible Apple Silicon Mac, and Apple Intelligence enabled. It is optional and always falls back to the original Whisper transcript if the model is unavailable, an error occurs, or the timeout is reached (4 seconds for Dictate, 30 seconds for Compose).

### Dictate or compose

In **Settings → Correction → Apple Intelligence**, turn on **Improve transcriptions with the on-device model**, then choose a mode:

- **Dictate** — clean up what you said, keeping the meaning and tone. This is the default.
- **Compose** — describe what you want to write and Loro turns it into an email, message, list, or rewritten text. Your choice is saved for next time.

For example, say “quiero mandar un mail a Juan preguntándole si puede entregar el presupuesto para el viernes”. Dictate keeps that sentence; Compose can produce:

> Hola, Juan:
>
> ¿Podrías enviarme el presupuesto para el viernes?
>
> Gracias.

Compose inserts the finished text at your cursor, just like dictation. It does not send emails or read the document you have open. Give it the details it needs: it is instructed to avoid inventing facts and to omit missing details or leave a placeholder. Check the result before sending it. If Apple Intelligence cannot complete the request, Loro inserts the original transcript instead.

## Privacy

- Audio exists only in memory while recording and transcription are in progress. Loro never writes it to disk.
- Transcripts are injected directly at the cursor. Loro does not log or persist them.
- Automatic clipboard copying is enabled by default and can be disabled in Settings. Loro writes only the latest result to the macOS pasteboard and keeps no separate clipboard history.
- There is no transcript history, telemetry, or cloud transcription.
- Apple Foundation Models correction runs on-device with no cloud API or network request. A fresh model session is used for each dictation.
- Correction context exists only in RAM: at most six recent fragments (about 800–1000 tokens), expiring after three minutes and resetting when the foreground app changes. **New Context**, changing modes, disabling correction, quitting, or `^C` clears it.
- Custom replacement rules are stored locally in app preferences because they are user configuration; they are never sent anywhere.
- Diagnostic events contain only failure categories, never audio or transcript content. They are available in macOS Console under `com.brunozapico.loro`.
- Installing or uninstalling the LaunchAgent removes log and WAV artifacts left by legacy versions.

Loro connects to Hugging Face only to download the selected WhisperKit model. Once downloaded, transcription runs locally through CoreML.

## Optional CLI

Everyday use needs no terminal. For diagnostics, model downloads, or login setup, the app includes its executable at `/Applications/Loro.app/Contents/MacOS/loro`. The separate CLI archive remains available for development; extract its resource bundles alongside the executable.

```sh
/Applications/Loro.app/Contents/MacOS/loro doctor
/Applications/Loro.app/Contents/MacOS/loro install --launch-at-login
/Applications/Loro.app/Contents/MacOS/loro install --uninstall
/Applications/Loro.app/Contents/MacOS/loro models list
/Applications/Loro.app/Contents/MacOS/loro models download whisper-small
```

The old `/usr/local/bin/loro` executable is no longer needed. Open the app to use the updated version. Direct CLI runs remain attached to their terminal session.

## Recovery and limits

- Input-device changes finish the current recording; the next recording uses a fresh audio engine.
- A recording is capped at five minutes (16 kHz mono in memory).
- Correction falls back to the original transcript after 4 seconds in Dictate or 30 seconds in Compose, even if the framework does not promptly cancel.
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
scripts/setup-local-signing.sh # once per signing Mac
scripts/test-signing.sh
scripts/build-app.sh 0.3.1
open dist/Loro-macos-arm64.dmg
```

To also test email and list composition with the real Apple model, run `LORO_RUN_CORRECTION_TESTS=1 scripts/test.sh` on a Mac where Apple Intelligence is ready. Both modes also work in Low Power Mode.

The build creates `Loro.app`, a drag-to-Applications DMG, a ZIP and checksums in `dist/`. CI runs tests and creates test artifacts on every push to main. Publish installer assets from the signing Mac; tagged CI builds cannot replace them with ad-hoc binaries. Set `CODESIGN_IDENTITY` to a Developer ID identity for signing; notarization is a separate distribution step.

### Stable permissions across updates

Keep the same signing certificate when building updates. Ad-hoc signatures identify each binary by its hash, so rebuilding used to invalidate Accessibility even when System Settings still showed Loro as enabled. Local builds now reuse a certificate kept in your login keychain and refuse to silently fall back to ad-hoc signing. Keep that keychain; creating a new certificate changes the identity again. For public distribution, use the same Developer ID identity across releases. CI creates explicitly ad-hoc test artifacts and cannot overwrite signed releases.

When migrating from an old ad-hoc version, remove the old Loro entry in **System Settings → Privacy & Security → Accessibility**, add **/Applications/Loro.app**, and enable it once. Reopen Loro afterward. Do not add the old `/usr/local/bin/loro` for the native app. Loro cannot grant itself this permission.

The shortcut now runs on its own thread, so starting the microphone cannot stall its event tap. If macOS suspends the tap, Loro checks whether the shortcut is still physically held instead of ending the recording immediately. Diagnostic logs include the reason recording stopped, but never the audio or transcript.
