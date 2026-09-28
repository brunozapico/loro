# Stability investigation and macOS application

## Evidence and limits

The inspected baseline is `3da6234`. No Loro/parrot crash reports were retained in the Mac's DiagnosticReports directories. The installed LaunchAgent reported its last exit as successful (0), which does not establish the cause of earlier unexpected exits. The old CLI process is also tied to the lifetime of the launching terminal. The fixes below address observable defects in source, not a claim that every past crash has been reproduced.

## Defects addressed

- Startup blocked the main thread on a semaphore before starting AppKit. Model download/prewarming left no responsive UI. AppKit now starts immediately; asynchronous loading has a five-minute deadline and a visible failure state.
- Correction used a task group as a four-second timeout. Structured task groups wait for every child, so a framework ignoring cancellation defeats that timeout. `TimedOperation` returns at the deadline and retains a single-worker gate until underlying work actually finishes. The same mechanism bounds transcription waiting at two minutes, preventing overlapping model work after a timeout.
- Audio capture did not reject zero-rate/zero-channel input formats, handle engine configuration changes, or bound recording length. Device changes could stop the engine while the controller remained recording. Engine start operations can raise Objective-C exceptions that Swift `catch` cannot intercept. Those calls now live behind a small Objective-C boundary; each recording has a fresh engine and synchronized, five-minute buffer. Late callbacks cannot modify a later recording.
- Disabled event taps retained their pressed state. A missed release could leave push-to-talk active. Recovery now releases the held state and respects explicit disabling during shortcut editing; stopping invalidates the event tap.
- A delayed overlay hide could hide the next recording's overlay. Visibility revisions discard obsolete animation callbacks.
- The release workflow packaged only the executable, omitting SwiftPM runtime resource bundles. The application and CLI archives now include dependency resources.
- Multiple launches could compete for the microphone and event tap. Current builds share an advisory instance lock, and app launches activate the existing instance.

## Application lifecycle and distribution

`Loro.app` includes its identity, microphone purpose string, icon, standard application/Edit menus and Dock presence. Closing Settings leaves dictation available. Command-Q and termination signals stop capture, cancel pending delivery and clear volatile correction context. Reopening from the Dock shows Settings.

Installed app launches migrate an existing Loro login agent to `/usr/bin/open -a <app>`, without KeepAlive. Development copies do not rewrite login configuration. Preferences and existing model caches retain their paths. Old binaries already running must be quit before upgrading; older versions do not implement the instance lock.

`scripts/build-app.sh` builds and verifies the app, DMG, ZIP, CLI archive and SHA-256 checksums. Builds are ad-hoc signed by default: there is no Developer ID certificate configured on the development machine, and no Apple notarization is claimed. Downloaded builds may need explicit Gatekeeper approval. Microphone and Accessibility permissions must be granted to the app identity.

## Validation

Run `scripts/test.sh` for the existing behavior tests and regressions covering bounded audio, late callbacks, concurrent stop, uncooperative inference timeouts, single-worker exclusion and cancellation. The script supports Swift Testing in Command Line Tools as well as full Xcode. Run `scripts/build-app.sh 0.2.0` for release packaging, signature verification and plist validation.

Manual checks should include launching outside the source tree, closing/reopening Settings, Command-Q and relaunch, denied/granted microphone permission, recording and transcription, and changing an audio device during capture. Hardware-specific disconnects and multi-hour usage cannot be established by unit tests alone.

References: [Swift TaskGroup semantics](https://developer.apple.com/documentation/swift/taskgroup), [audio engine configuration changes](https://developer.apple.com/documentation/foundation/nsnotification/name-swift.struct/avaudioengineconfigurationchange), [microphone purpose string](https://developer.apple.com/documentation/BundleResources/Information-Property-List/NSMicrophoneUsageDescription).

### Local validation result

On the development Mac, all 29 tests passed, including real WhisperKit transcription of a synthetic English phrase. First-use Neural Engine compilation took approximately 163 seconds; a process sample confirmed CoreML/ANE compilation rather than a blocked AppKit main thread. The default CI suite skips that opt-in model test to avoid downloading large models. Enable it with `LORO_RUN_MODEL_TESTS=1 scripts/test.sh`.

The app build uses a small compiler wrapper only to adjust SwiftPM-generated resource accessors from the CLI bundle root to `Bundle.main.resourceURL`. Resources therefore stay under `Contents/Resources`, which macOS signing requires. Packaging stages outside synced Documents folders to prevent File Provider metadata from invalidating the signature.

A native-package smoke test caught an additional migration regression before release: `UserDefaults(suiteName:)` returned nil when the suite matched the new app's own bundle identifier, and the old force unwrap trapped. The app now uses `UserDefaults.standard` for its own domain and retains the named-suite path for CLI use. A regression test covers this; the final suite contains 30 tests (the model integration test is opt-in).
