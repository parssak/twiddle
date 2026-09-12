#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Lowpasser.app"
mkdir -p "$PWD/build"
staging=$(mktemp -d "$PWD/build/.lowpasser.XXXXXX")
trap 'rm -rf "$staging"' EXIT
candidate="$staging/Lowpasser.app"
mkdir -p "$candidate/Contents/MacOS"
clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=26.0 \
    -framework Cocoa -framework CoreAudio -framework CoreGraphics \
    main.m AppDelegate.m FilterKnob.m AudioEngine.m FnKeyMonitor.m Tests.m \
    -o "$candidate/Contents/MacOS/Lowpasser"
cp Info.plist "$candidate/Contents/Info.plist"
mkdir -p "$candidate/Contents/Resources"
cp Assets/AppIcon.icns "$candidate/Contents/Resources/AppIcon.icns"
cp Assets/KnobMetal.png "$candidate/Contents/Resources/KnobMetal.png"
bash scripts/sign-app.sh "$candidate"
"$candidate/Contents/MacOS/Lowpasser" --self-test
if [[ -e "$app" ]]; then mv "$app" "$staging/previous.app"; fi
if ! mv "$candidate" "$app"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$app"; fi
    exit 1
fi
printf '\nBuilt %s\nRun: open "%s"\n' "$app" "$app"
