<img src="Assets/AppIcon.png" width="96" alt="Twiddle icon">

<h1><img src="Assets/TwiddleWordmark.svg" width="221" alt="Twiddle"></h1>

A little DJ filter for your Mac’s menu bar. Turn the knob to cut the highs or lows, or use a hold shortcut to drop into a preset and ease back when you let go.

**[Download Twiddle](https://github.com/parssak/twiddle/releases/latest)** · Apple Silicon · macOS 26+

v0.3 adds app-triggered filtering, refreshed Settings, interactive disco mode with album colours, a CLI, and shortcut permission controls.

<img src="docs/screenshot.png" width="520" alt="Twiddle in the macOS menu bar, filtering Spotify with a brushed-metal knob">

## Install

Open the DMG, drag Twiddle into Applications, and launch it. The download is signed and notarized by Apple.

Allow system audio recording when macOS asks. Twiddle also asks for access to Spotify so it can show the current song in the popover. Allow Accessibility to use ⌥F10–F12 directly on a media-key top row; if you set a hold shortcut, enable Input Monitoring. For top-row shortcuts, General settings shows **Allow Accessibility…** when access is missing and opens the correct System Settings pane. Twiddle retries the listener after access is granted; **Retry Shortcuts** is available if the listener still fails. Other permission changes may require reopening Twiddle.

## Use

- **Turn the knob:** left for low-pass, right for high-pass, center for the original audio. Drag or scroll; hold Shift for finer control.
- **Double-click:** smoothly reset to center.
- **⌥F10 / ⌥F11 / ⌥F12:** toggle between bypass and your preset, step down, or step up from anywhere. The menu-bar popover briefly shows each change.
- **Click the source icon:** choose which apps get filtered and which apps trigger the preset.
- **Click the cog:** open Settings. Set the preset with its own knob, then use the hold shortcut to activate it.
- **Right-click the menu bar icon:** open Settings, manage the hold shortcut, or quit.

When Spotify is the first target app, the footer shows its current song. Adjusting the knob temporarily replaces it with the filter frequency, then blurs back to the song after a second. Long names stay pinned to the beginning, then scroll after a brief hover pause.

Settings has General and Auto-apply pages. General contains Apps to Twiddle. Auto-apply starts with the filter preset, followed by separate microphone, hold-shortcut, and trigger-app cards. You can record or clear the hold shortcut (None by default), choose your low/high colors, and choose audio apps in two grids. **Apps to Twiddle** selects which apps get filtered; **Apps that trigger Twiddle** holds the preset while any listed app is producing audio. Drag application bundles from Finder into either grid or use + Apps, and hover over an app and click it to remove it. Your previous default app becomes the initial target. Empty targets stop filtering; empty triggers disable playback automation. A shared level monitor releases the preset after 300 ms of silence, followed by a 180 ms fade; silent streams do not hold the preset. New installs enable Open at Login and trackpad haptics; either can be turned off in Settings. macOS may require approval for the login item.

The first Settings row opens macOS Menu Bar settings, where the system's “Allow in the Menu Bar” switch controls Twiddle's icon. If the icon is unavailable, reopening Twiddle from Applications, Spotlight, or Raycast opens that page directly.

**Apply when mic is active** applies the preset while **Any app** or **Wispr Flow** has an active audio input. It starts in Wispr Flow mode, enabled when Flow is installed; existing preferences are preserved. Twiddle excludes its own capture. This is experimental: virtual audio inputs and apps that keep their mic open while silent or muted can also activate it. The preset returns to your previous setting after all playback, microphone, and shortcut triggers release.

Light trackpad haptics mark each tick. Filtering stays active when the popover closes. No audio is saved or uploaded.

This is an early release. Built-in speakers and wired stereo headphones are the best starting point; Bluetooth and multichannel setups haven’t been validated.

## CLI

Twiddle includes a CLI for users and agents: `twiddle status`, `twiddle set -0.5`, `twiddle apply`, `twiddle reset`, and `twiddle disco on`. `bash install.sh` installs the command into `~/.local/bin`. See [CLI usage and JSON responses](docs/CLI.md).

## Build

With Xcode command-line tools installed:

```sh
bash build.sh
open build/Twiddle.app
```

No dependencies to install. See [development notes](docs/DEVELOPMENT.md) for local installation, signing, and release packaging.
