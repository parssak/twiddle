<img src="Assets/AppIcon.png" width="96" alt="Twiddle icon">

<h1><img src="Assets/TwiddleWordmark.svg" width="221" alt="Twiddle"></h1>

A little DJ filter for your Mac’s menu bar. Turn the knob to cut the highs or lows, or use a hold shortcut to drop into a preset and ease back when you let go.

**[Download Twiddle](https://github.com/parssak/twiddle/releases/latest)** · Apple Silicon · macOS 26+

The DMG is v0.1. The Settings window and microphone trigger described below are currently available in source builds.

<img src="docs/screenshot.png" width="520" alt="Twiddle in the macOS menu bar, filtering Spotify with a brushed-metal knob">

## Install

Open the DMG, drag Twiddle into Applications, and launch it. The download is signed and notarized by Apple.

Allow system audio recording when macOS asks. Twiddle also asks for access to Spotify so it can show the current song in the popover. Allow Accessibility to use ⌥F10–F12 directly on a media-key top row; if you set a hold shortcut, enable Input Monitoring. Reopen Twiddle after changing a system permission.

## Use

- **Turn the knob:** left for low-pass, right for high-pass, center for the original audio. Drag or scroll; hold Shift for finer control.
- **Double-click:** smoothly reset to center.
- **⌥F10 / ⌥F11 / ⌥F12:** toggle between bypass and your preset, step down, or step up from anywhere. The menu-bar popover briefly shows each change.
- **Click the source icon:** switch between your default app and all Mac audio.
- **Click the cog:** open Settings. Set the preset with its own knob, then use the hold shortcut to activate it.
- **Right-click the menu bar icon:** open Settings, manage the hold shortcut, or quit.

When Spotify is the default app, the footer shows its current song. Adjusting the knob temporarily replaces it with the filter frequency, then blurs back to the song after a second. Long names stay pinned to the beginning, then scroll after a brief hover pause.

Settings is split into General and Automatic Preset pages. You can record or clear the hold shortcut (None by default), choose your low/high colors, and pick Spotify, Music, Chrome, Arc, or Dia as your default app. Apps that aren’t installed are unavailable. New installs enable Open at Login and trackpad haptics; either can be turned off in Settings. macOS may require approval for the login item.

Hover over the Twiddle wordmark for the disco Easter egg. Its Metal animation is fully local and permission-free.

The first Settings row opens macOS Menu Bar settings, where the system's “Allow in the Menu Bar” switch controls Twiddle's icon. If the icon is unavailable, reopening Twiddle from Applications, Spotlight, or Raycast opens that page directly.

**Apply when mic is active** applies the preset while **Any app** or **Wispr Flow** has an active audio input. It starts in Wispr Flow mode, enabled when Flow is installed; existing preferences are preserved. Twiddle excludes its own capture. This is experimental: virtual audio inputs and apps that keep their mic open while silent or muted can also activate it. The preset returns to your previous setting after both microphone activity and the hold shortcut release.

Light trackpad haptics mark each tick. Filtering stays active when the popover closes. No audio is saved or uploaded.

This is an early release. Built-in speakers and wired stereo headphones are the best starting point; Bluetooth and multichannel setups haven’t been validated.

## Build

With Xcode command-line tools installed:

```sh
bash build.sh
open build/Twiddle.app
```

No dependencies to install. See [development notes](docs/DEVELOPMENT.md) for local installation, signing, and release packaging.
