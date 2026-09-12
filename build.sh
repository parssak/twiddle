#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Twiddle.app"
mkdir -p "$PWD/build"
staging=$(mktemp -d "$PWD/build/.twiddle.XXXXXX")
trap 'rm -rf "$staging"' EXIT
candidate="$staging/Twiddle.app"
mkdir -p "$candidate/Contents/MacOS"
clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=26.0 \
    -framework Cocoa -framework CoreAudio -framework CoreGraphics -framework ServiceManagement \
    main.m AppDelegate.m SettingsController.m FilterKnob.m AudioEngine.m WisprActivity.m HoldShortcutMonitor.m Tests.m \
    -o "$candidate/Contents/MacOS/Twiddle"
cp Info.plist "$candidate/Contents/Info.plist"
mkdir -p "$candidate/Contents/Resources"
cp Assets/AppIcon.icns "$candidate/Contents/Resources/AppIcon.icns"
cp Assets/KnobMetal.png "$candidate/Contents/Resources/KnobMetal.png"
if [[ -n "${TWIDDLE_SIGN_IDENTITY:-}" ]]; then
    [[ "$TWIDDLE_SIGN_IDENTITY" == 'Developer ID Application: '* ]] || {
        echo 'Release signing requires a Developer ID Application identity.' >&2
        exit 1
    }
    codesign --force --options runtime --timestamp --sign "$TWIDDLE_SIGN_IDENTITY" "$candidate"
    codesign --verify --strict "$candidate"
else
    bash scripts/sign-app.sh "$candidate"
fi
"$candidate/Contents/MacOS/Twiddle" --self-test
if [[ -e "$app" ]]; then mv "$app" "$staging/previous.app"; fi
if ! mv "$candidate" "$app"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$app"; fi
    exit 1
fi
printf '\nBuilt %s\nRun: open "%s"\n' "$app" "$app"
