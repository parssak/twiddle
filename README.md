# Lowpasser

A dependency-free macOS app that captures audio sent to the current output using a Core Audio process tap,
mutes the original while active, applies a 12 dB/octave low/high-pass filter, and
plays it through a private aggregate containing the current output device.
The tap targets the output stream directly so capture and playback sample rates match.

```sh
bash build.sh
open build/Lowpasser.app
```

To install in Applications for Spotlight and Raycast, quit any running copy, then:

```sh
bash install.sh
open /Applications/Lowpasser.app
```

Run the same install command after changes to rebuild and update the installed app.
It preserves the local signing identity used for macOS permissions.

Click the filter icon in the menu bar to open the native glass popover. The Spotify
and computer icons select Spotify only or all Mac audio. The power button turns
processing on or off; turning it off eases back to bypass before releasing the audio
route. The source and power choices are remembered across launches. Grant system
audio recording permission when macOS asks, then reopen if required.

The upper slider controls and displays the current filter. Move left to remove treble,
right to remove bass; the center is bypass. The lower Fn slider sets the held preset
without changing current audio. Holding Fn eases toward that preset over 180 ms;
releasing returns to the previous setting over 400 ms. Changing the preset during a
hold lets you hear it without changing the return setting. The preset is remembered.
Turning power off cancels the hold and resets the filter over 180 ms. The DSP adds a
short smoothing stage to these transitions.

Right-click the menu bar icon for **Fn shortcut**, **Input Monitoring…**, and **Quit
Lowpasser**. Enable Input Monitoring for Lowpasser in System Settings if needed, then
reopen if macOS asks. An orange Fn icon means the shortcut isn't enabled. The listener
observes only modifier changes and doesn't suppress the keyboard's existing Fn/Globe
action; set "Press Globe key to" to "Do Nothing" in Keyboard settings if desired.
Closing the popover keeps processing active; quitting releases the audio route.

This personal prototype supports stereo float audio and rejects other layouts. Start
with built-in speakers or wired headphones. It restarts processing when the output
changes and resumes after sleep if power is enabled. Bluetooth, physical sleep/wake,
protected content, multichannel devices, and latency are not validated. The app doesn't
change your default output, save audio, or use the network.

`build/Lowpasser.app/Contents/MacOS/Lowpasser --probe` checks the current route's formats
without starting audio capture. The build checks filter behavior at 44.1 and 48 kHz.

The build uses a persistent **Lowpasser Local Development** certificate instead of
ad-hoc signing. `scripts/sign-app.sh` creates it once in a dedicated local keychain,
then reuses it. The app's designated requirement pins that certificate and the bundle
identifier, so its code identity remains the same when its contents change. Switching
from the old ad-hoc build requires granting permissions once for this new identity.

Signing state lives outside the repository:

- Certificate and owner-only keychain password: `~/Library/Application Support/Lowpasser/Signing/`.
- Non-exportable private key: `~/Library/Keychains/lowpasser-local-signing.keychain-db`.

Keep those files to preserve the identity. The certificate is trusted only for code
signing in your user account, and this remains a local development build, not an
Apple Developer ID/notarized release. The script never falls back to ad-hoc signing.
Builds are signed and checked in a staging directory before replacing the app, so a
failed build leaves the previous app available and doesn't overwrite its executable.

Requires Xcode command-line tools and macOS 26+ for bundle-based app selection and
process restoration. No package installation is needed.

Code boundaries:

- `AudioEngine`: tap and playback lifecycle, format validation, real-time callback.
- `Filter.h`: DSP; `FilterControl.h`: baseline, held preset, and transitions.
- `FnKeyMonitor`: permission and global modifier listening.
- `AppDelegate`: menu bar, popover, and control/route coordination.
- `Assets`: the supplied app icon and its macOS icon bundle.

The build checks DSP at both sample rates, reset settling, hold/release state, repeated
modifier events, and listener cleanup. Event-decoder tests do not prove physical Fn
delivery or bypass macOS's Input Monitoring permission.
