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

Click the filter icon in the menu bar to open the native glass popover. The source
button shows the current selection; click it to cycle between Spotify only and all
Mac audio. This choice is remembered. Filtering stays active while the app is running;
quit Lowpasser to release the route. Grant system audio recording permission when macOS
asks, then reopen if required.

The rotary knob controls and displays the current filter. Turn counterclockwise to
remove treble, clockwise to remove bass; twelve o'clock is bypass. Drag vertically or
scroll to turn it, hold Shift for fine adjustments, and double-click to center it.
Arrow keys also adjust the focused knob; Return centers it. Resetting the live filter
with double-click or Return eases back to bypass over 180 ms. Crossing a tick on the arc
while adjusting gives light haptic feedback on a supported trackpad, including at the
limits. Automatic Fn transitions don't trigger haptics.
The menu bar icon mirrors the knob's position, including Fn transitions and preset editing.

Toggle the **cog icon** to edit the remembered held preset instead. The knob turns purple
in this mode; editing doesn't change current audio unless Fn is held for a preview.
Toggle it off to return to the current filter. Holding Fn eases toward the preset over
180 ms; releasing restores the previous setting over 400 ms. Changing the preset during
a hold still preserves the return setting.
The DSP adds a short smoothing stage to these transitions.

Right-click the menu bar icon for **Fn shortcut**, **Input Monitoring…**, and **Quit
Lowpasser**. Enable Input Monitoring for Lowpasser in System Settings if needed, then
reopen if macOS asks. An orange cog means the shortcut isn't enabled. The listener
observes only modifier changes and doesn't suppress the keyboard's existing Fn/Globe
action; set "Press Globe key to" to "Do Nothing" in Keyboard settings if desired.
Closing the popover keeps processing active; quitting releases the audio route.

This personal prototype supports stereo float audio and rejects other layouts. Start
with built-in speakers or wired headphones. It restarts processing when the output
changes and resumes after sleep. Bluetooth, physical sleep/wake,
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
- `FilterKnob`: rotary drawing, mouse/keyboard input, and accessibility.
- `Assets`: the supplied app icon and its macOS icon bundle, plus an imagegen brushed-aluminum texture for the knob face. Lighting stays fixed while the pointer rotates.

The build checks DSP at both sample rates, reset settling, hold/release state, repeated
modifier events, and listener cleanup. Event-decoder tests do not prove physical Fn
delivery or bypass macOS's Input Monitoring permission.
