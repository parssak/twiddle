#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
app="$PWD/build/Twiddle.app"
mkdir -p "$PWD/build"
sparkle_root=$(bash scripts/prepare-sparkle.sh)
staging=$(mktemp -d "$PWD/build/.twiddle.XXXXXX")
trap 'rm -rf "$staging"' EXIT
candidate="$staging/Twiddle.app"
mkdir -p "$candidate/Contents/MacOS"
sources=(Sources/App/*.m Sources/UI/*.m Sources/Audio/*.m Tests/*.m)
clang -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=26.0 \
    -framework Cocoa -framework Carbon -framework AudioToolbox -framework CoreAudio -framework CoreGraphics -framework CoreImage -framework IOKit -framework Metal -framework MetalKit -framework QuartzCore -framework ServiceManagement \
    -F "$sparkle_root" -framework Sparkle '-Wl,-rpath,@executable_path/../Frameworks' \
    -I Sources/App -I Sources/UI -I Sources/Audio "${sources[@]}" \
    -o "$candidate/Contents/MacOS/Twiddle"
cp Info.plist "$candidate/Contents/Info.plist"
mkdir -p "$candidate/Contents/Resources"
cp Assets/AppIcon.icns "$candidate/Contents/Resources/AppIcon.icns"
cp Assets/KnobMetal.png "$candidate/Contents/Resources/KnobMetal.png"
cp Assets/TwiddleWordmark.svg "$candidate/Contents/Resources/TwiddleWordmark.svg"
cp "$sparkle_root/LICENSE" "$candidate/Contents/Resources/Sparkle-LICENSE.txt"
mkdir -p "$candidate/Contents/Frameworks"
ditto "$sparkle_root/Sparkle.framework" "$candidate/Contents/Frameworks/Sparkle.framework"
if [[ -n "${TWIDDLE_SIGN_IDENTITY:-}" ]]; then
    [[ "$TWIDDLE_SIGN_IDENTITY" == 'Developer ID Application: '* ]] || {
        echo 'Release signing requires a Developer ID Application identity.' >&2
        exit 1
    }
    sign_timestamp=${TWIDDLE_SIGN_TIMESTAMP:-secure}
    TWIDDLE_SIGN_TIMESTAMP="$sign_timestamp" bash scripts/sign-sparkle.sh "$candidate" "$TWIDDLE_SIGN_IDENTITY"
    release_sign=(codesign --force --options runtime --entitlements Twiddle.entitlements \
        --sign "$TWIDDLE_SIGN_IDENTITY")
    if [[ "$sign_timestamp" == none ]]; then release_sign+=(--timestamp=none); else release_sign+=(--timestamp); fi
    if [[ -n "${TWIDDLE_SIGN_KEYCHAIN:-}" ]]; then release_sign+=(--keychain "$TWIDDLE_SIGN_KEYCHAIN"); fi
    "${release_sign[@]}" "$candidate"
    codesign --verify --deep --strict "$candidate"
else
    bash scripts/sign-app.sh "$candidate"
fi
"$candidate/Contents/MacOS/Twiddle" --self-test
otool -L "$candidate/Contents/MacOS/Twiddle" | grep -q '@rpath/Sparkle.framework/Versions/B/Sparkle'
if [[ -e "$app" ]]; then mv "$app" "$staging/previous.app"; fi
if ! mv "$candidate" "$app"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$app"; fi
    exit 1
fi
printf '\nBuilt %s\nRun: open "%s"\n' "$app" "$app"
