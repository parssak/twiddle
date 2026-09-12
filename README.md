<img src="Assets/AppIcon.png" width="96" alt="Twiddle icon">

# Twiddle

A little DJ filter for your Mac’s menu bar. Turn the knob to cut the highs or lows, or hold Fn to drop into a preset and ease back when you let go.

**[Download Twiddle](https://github.com/parssak/twiddle/releases/latest)** · Apple Silicon · macOS 26+

<img src="docs/screenshot.png" width="520" alt="Twiddle in the macOS menu bar, filtering Spotify with a brushed-metal knob">

## Install

Open the DMG, drag Twiddle into Applications, and launch it. The download is signed and notarized by Apple.

Allow system audio recording when macOS asks. For the Fn shortcut, also enable Twiddle in **System Settings → Privacy & Security → Input Monitoring**, then reopen it if prompted.

## Use

- **Turn the knob:** left for low-pass, right for high-pass, center for the original audio. Drag or scroll; hold Shift for finer control.
- **Double-click:** smoothly reset to center.
- **Click the source icon:** switch between Spotify and all Mac audio.
- **Click the cog:** set your Fn preset. Click it again to return to the live knob, then hold Fn to use the preset.
- **Right-click the menu bar icon:** manage the Fn shortcut or quit.

Light trackpad haptics mark each tick. Filtering stays active when the popover closes. No audio is saved or uploaded.

This is an early release. Built-in speakers and wired stereo headphones are the best starting point; Bluetooth and multichannel setups haven’t been validated.

## Build

With Xcode command-line tools installed:

```sh
bash build.sh
open build/Twiddle.app
```

No dependencies to install. See [development notes](docs/DEVELOPMENT.md) for local installation, signing, and release packaging.
