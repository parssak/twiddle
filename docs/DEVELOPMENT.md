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

Builds run DSP checks at 44.1 and 48 kHz, plus hold/release, reset interruption, and listener cleanup checks. These do not validate physical Fn delivery, device compatibility, or end-to-end audio latency.

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
TWIDDLE_SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
TWIDDLE_NOTARY_PROFILE='twiddle-notary' bash package.sh --release
```

The script enables hardened runtime, adds secure timestamps, submits the DMG to Apple, staples its ticket, and checks Gatekeeper. Output is `build/Twiddle-<version>-<architecture>.dmg`, with a SHA-256 checksum and notarization result alongside it. A failed release preserves its candidate DMG for inspection or finishing a delayed submission. Builds target the host architecture.

## Code

- `AudioEngine`: capture/playback lifecycle, format validation, and real-time callback.
- `Filter.h` / `FilterControl.h`: DSP and smooth live/preset transitions.
- `HoldShortcutMonitor`: Input Monitoring permission and held shortcuts.
- `GlobalFilterHotkeys`: fixed ⌥F10 preset toggle and ⌥F11–F12 stepped filter controls. It registers ordinary function-key hotkeys and, with Accessibility permission, consumes the equivalent mute/volume media-key events so Fn is unnecessary.
- `AppDelegate` / `FilterKnob`: menu bar, popover, knob, and haptics.
- `SpotifyNowPlaying`: reads the current Spotify track over Apple events while the popover is open.
- `SettingsController`: floating settings window, preset knob, shortcut recorder, colors, and installed-app picker.
- `DiscoOverlay`: the permission-free Metal disco overlay shown from the Settings wordmark.
- `MicrophoneActivity`: polls Core Audio process input activity for any app or Flow and its helpers, excluding Twiddle by PID and bundle ID. It does not capture audio.

The shortcut and microphone activity share the preset through separate trigger bits. Releasing one cannot restore the baseline while the other remains active; reset suppresses active triggers until both release. Microphone activity is checked four times per second using public Core Audio process properties. A process must report both active input and a nonempty input-device list; device-less background services such as CoreSpeech do not qualify. This detects active input streams, including virtual inputs, rather than speech or in-app mute state. The legacy `followWisprFlow` preference migrates once to `microphoneEnabled`; `microphoneScope` defaults to `wispr` and also supports `any`.

The app supports stereo float audio and rejects unsupported layouts. It restarts processing when the output changes and resumes after sleep. Bluetooth, physical sleep/wake, protected content, multichannel devices, and latency need broader testing.
