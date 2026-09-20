# Development

Twiddle uses Objective-C, AppKit, and a Core Audio process tap. It mutes the captured audio, applies a 12 dB/octave low/high-pass filter, and plays it through a private aggregate containing the current output. Requires macOS 26+ and Xcode command-line tools.

## Build and install

```sh
bash build.sh
open build/Twiddle.app
```

To install for Spotlight and Raycast, quit any running copy, then:

```sh
bash install.sh
open /Applications/Twiddle.app
```

The first build downloads the pinned Sparkle 2.10.0 binary distribution into the ignored `build/dependencies/` cache and verifies its published SHA-256 before use. Builds run DSP checks at 44.1, 48, and 96 kHz, plus hold/release, reset interruption, and listener cleanup checks. These do not validate physical Fn delivery, device compatibility, or end-to-end audio latency.

To inspect the current route without starting capture:

```sh
build/Twiddle.app/Contents/MacOS/Twiddle --probe
```

## Local signing

`scripts/sign-app.sh` creates a persistent local code-signing certificate in a dedicated user keychain. Reusing it keeps the app’s identity stable across rebuilds. Signing state lives outside the repository:

- `~/Library/Application Support/Twiddle/Signing/`
- `~/Library/Keychains/twiddle-local-signing.keychain-db`

Existing installations from before the rename reuse the equivalent `Lowpasser` paths and certificate. The internal bundle identifier remains `com.parssa.lowpasser.poc` to preserve preferences and permission grants. Keep the signing state; switching certificates can require granting permissions again.

## Package a release

For a locally signed drag-to-Applications DMG:

```sh
bash package.sh
```

For a public download, install a Developer ID Application identity and save notarization credentials to Keychain. The following command prompts securely for an Apple app-specific password:

```sh
xcrun notarytool store-credentials twiddle-notary \
  --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
```

Then build, sign, and notarize:

```sh
bash scripts/release.sh
```

The wrapper unlocks the dedicated local signing keychain without exposing its password, then enables hardened runtime, signs Sparkle from the inside out, submits the DMG to Apple, staples its ticket, and checks Gatekeeper. It uses the EdDSA key stored under the `com.parssa.twiddle` Keychain account, or its mode-600 release backup under Application Support for headless signing, to generate the signed `site/appcast.xml`. Output is `build/Twiddle-<version>-<architecture>.dmg`, with a SHA-256 checksum and notarization result alongside it. Builds target the host architecture.

Submission state is written before waiting on Apple. If the agent or terminal disconnects while Apple is processing the build, `bash scripts/release.sh --resume` continues the same submission instead of uploading and notarizing the DMG again. Override the wrapper defaults with the existing `TWIDDLE_SIGN_*` and `TWIDDLE_NOTARY_PROFILE` environment variables when moving the release process to another Mac.

Publish the GitHub release before deploying `site/`, because the generated appcast points at the versioned GitHub DMG. Private signing material stays local; only `SUPublicEDKey` belongs in `Info.plist`.

## Source layout

- `Sources/App/`: application lifecycle, global shortcuts, Spotify integration, and Sparkle update control.
- `Sources/UI/`: Settings, the filter knob, app grids, shortcut recorder, wordmark, marquee, and visual effects. `SettingsLayout` owns shared card/row construction and spacing constants.
- `Sources/Audio/`: capture/playback, DSP and preset state, process discovery, and playback-level monitoring. `AudioProcessActivity` supplies both microphone activity and candidate playback processes.
- `Tests/`: self-tests compiled into the app and run with `--self-test` during builds.
- `Assets/`: packaged app resources. `site/` contains the separate website.

`build.sh` compiles the Objective-C files in those source directories and copies the resources into the app bundle. Adding a source file within a directory does not require updating a hand-maintained compiler command.

## Code

- `AudioEngine`: capture/playback lifecycle, format validation, and real-time callback.
- `Filter.h` / `FilterControl.h`: DSP and smooth live/preset transitions.
- `HoldShortcutMonitor`: Input Monitoring permission and held shortcuts.
- `GlobalFilterHotkeys`: fixed ⌥F10 preset toggle and ⌥F11–F12 stepped filter controls. It registers ordinary function-key hotkeys and, with Accessibility permission, consumes the equivalent mute/volume media-key events so Fn is unnecessary.
- `AppDelegate` / `FilterKnob`: menu bar, popover, knob, and haptics.
- `SpotifyNowPlaying`: reads the current Spotify track over Apple events while the popover is open.
- `SettingsController`: settings navigation, card layout, and preference callbacks; standalone views handle app grids, shortcut recording, and the wordmark.
- `DiscoOverlay`: the permission-free Metal disco overlay shown from the Settings wordmark. Drag the ball to stretch and tilt the cord; crossing the pull threshold releases it and cycles the beam palette. Progressive haptic detents honor Trackpad Haptics. Two-finger swipes over the ball add bounded spin momentum in either direction, then decay back to its normal rotation; system scroll momentum is ignored. `DiscoMotion` owns the normalized pull, damped return, and single-trigger latch; short clicks and Escape still dismiss the overlay. `DiscoNowPlaying` displays large Spotify song and artist text with asynchronously loaded album artwork at the bottom left of each display, blurs and fades on entry and exit, polls only while disco mode is visible, and hides paused or unavailable tracks. `AlbumPalette` samples each downloaded cover at 32×32, selects up to four saturated accents, and passes them to the rays with an 0.8-second blend. Pulling cycles album colours, warm, cool, and rainbow modes. Album mode falls back to white for monochrome or missing artwork. Only current artwork colours and the in-flight palette blend are retained.
- `AudioProcessActivity`: polls Core Audio process input activity for any app or Flow and output activity for selected trigger apps, excluding Twiddle by PID and bundle ID. It does not capture audio.

The shortcut, microphone activity, and app playback share the preset through separate trigger bits. Playback polls `kAudioProcessPropertyIsRunningOutput` for `triggerBundles` to find candidate processes, including helper bundle IDs with a case-insensitive, dot-delimited app bundle prefix. `PlaybackActivity` uses one private, unmuted stereo mixdown tap for those processes, with no playback device attached. Its callback checks 32-bit float samples against -60 dBFS and atomically updates the last-sound timestamp. The UI checks that timestamp at 60 Hz: 300 ms of silence releases the playback trigger with a 180 ms fade. The monitor stops when no trigger streams are active, or filtering is stopped or suspended. Audio samples are never retained. `targetBundles` migrates from the previous `selectedBundle` and feeds the existing multi-bundle process tap. Releasing one cannot restore the baseline while another remains active; reset suppresses active triggers until all release. Microphone activity is checked four times per second using public Core Audio process properties. A process must report both active input and a nonempty input-device list; device-less background services such as CoreSpeech do not qualify. This detects active input streams, including virtual inputs, rather than speech or in-app mute state. The legacy `followWisprFlow` preference migrates once to `microphoneEnabled`; `microphoneScope` defaults to `wispr` and also supports `any`.

Idle control refresh runs at 4 Hz with timer tolerance; filter transitions and an active playback-monitor tap use 60 Hz. Process/route checks and metadata refreshes use elapsed-time deadlines, so their cadence does not depend on animation ticks. The refresh timer stops during sleep or an inactive session. Unused audio units stop rendering after their bypass fade and silent tail drain; pitch keeps the dry signal until its reported latency has filled on activation. The main audio route stays open for responsive controls, so bypass still has Core Audio callback overhead.

The app supports stereo float audio and rejects unsupported layouts. It restarts processing when the output changes and resumes after sleep. Bluetooth, physical sleep/wake, protected content, multichannel devices, and latency need broader testing.

`TwiddleControl` owns command parsing and the private Unix-socket transport. `AppDelegate` applies validated commands through the existing filter and settings controls. The app executable enters CLI mode with `--cli`, or when launched through the `twiddle` symlink. See [CLI.md](CLI.md) for the command contract.
