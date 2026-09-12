<img src="Assets/AppIcon.png" width="96" alt="Twiddle icon">

# Twiddle

A little DJ filter for your Mac’s menu bar. Turn the knob to cut the highs or lows, or hold Fn to drop into a preset and ease back when you let go.

**[Download Twiddle](https://github.com/parssak/twiddle/releases/latest)** · Apple Silicon · macOS 26+

The DMG is v0.1. The Settings window and Wispr Flow integration described below are currently available in source builds.

<img src="docs/screenshot.png" width="520" alt="Twiddle in the macOS menu bar, filtering Spotify with a brushed-metal knob">

## Install

Open the DMG, drag Twiddle into Applications, and launch it. The download is signed and notarized by Apple.

Allow system audio recording when macOS asks. For the Fn shortcut, also enable Twiddle in **System Settings → Privacy & Security → Input Monitoring**, then reopen it if prompted.

## Use

- **Turn the knob:** left for low-pass, right for high-pass, center for the original audio. Drag or scroll; hold Shift for finer control.
- **Double-click:** smoothly reset to center.
- **Click the source icon:** switch between your default app and all Mac audio.
- **Click the cog:** open Settings. Set the preset with its own knob, then use the hold shortcut to activate it.
- **Right-click the menu bar icon:** open Settings, manage the hold shortcut, or quit.

Settings lets you record or clear the hold shortcut (Fn by default), choose your low/high colors, and pick Spotify, Music, Chrome, Arc, or Dia as your default app. Apps that aren’t installed are unavailable. Open at Login and trackpad haptics are optional.

**Follow Wispr Flow** uses the same preset while macOS reports Flow’s microphone active, including hands-free sessions. This is experimental: microphone checks or other Flow recording features can also activate it. The preset returns to your previous setting after both Flow and the hold shortcut release.

Light trackpad haptics mark each tick. Filtering stays active when the popover closes. No audio is saved or uploaded.

This is an early release. Built-in speakers and wired stereo headphones are the best starting point; Bluetooth and multichannel setups haven’t been validated.

## Build

With Xcode command-line tools installed:

```sh
bash build.sh
open build/Twiddle.app
```

No dependencies to install. See [development notes](docs/DEVELOPMENT.md) for local installation, signing, and release packaging.
