#!/bin/bash
# With --release, sign and notarize using credentials already in Keychain.
set -euo pipefail
cd "$(dirname "$0")"
release=false
case "${1:-}" in
    '') unset TWIDDLE_SIGN_IDENTITY ;;
    --release)
        release=true
        : "${TWIDDLE_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
        : "${TWIDDLE_NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
        export TWIDDLE_SIGN_IDENTITY
        ;;
    *) echo 'Usage: bash package.sh [--release]' >&2; exit 1 ;;
esac
bash build.sh

app="$PWD/build/Twiddle.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(lipo -archs "$app/Contents/MacOS/Twiddle" | tr ' ' '-')
output="$PWD/build/Twiddle-$version-$architecture.dmg"
staging=$(mktemp -d "$PWD/build/.package.XXXXXX")
cleanup() {
    if $release && [[ -f "$staging/Twiddle.dmg" ]]; then
        printf '\nRelease did not finish. Preserved candidate: %s/Twiddle.dmg\n' "$staging" >&2
    else
        rm -rf "$staging"
    fi
}
trap cleanup EXIT
mkdir "$staging/contents"
ditto "$app" "$staging/contents/Twiddle.app"
ln -s /Applications "$staging/contents/Applications"
codesign --verify --strict "$staging/contents/Twiddle.app"
hdiutil create -volname Twiddle -srcfolder "$staging/contents" \
    -fs HFS+ -format UDZO "$staging/Twiddle.dmg"
hdiutil verify "$staging/Twiddle.dmg"
if $release; then
    codesign --timestamp --sign "$TWIDDLE_SIGN_IDENTITY" "$staging/Twiddle.dmg"
    xcrun notarytool submit "$staging/Twiddle.dmg" --keychain-profile "$TWIDDLE_NOTARY_PROFILE" \
        --wait --timeout 15m --output-format json > "$output.notary.json"
    /usr/bin/python3 - "$output.notary.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    submission = json.load(f)
if submission.get('status') != 'Accepted':
    sys.exit('Notarization not accepted; inspect ' + sys.argv[1])
PY
    xcrun stapler staple "$staging/Twiddle.dmg"
    xcrun stapler validate "$staging/Twiddle.dmg"
    spctl --assess --type open --context context:primary-signature "$staging/Twiddle.dmg"
fi
mv "$staging/Twiddle.dmg" "$output"
(cd build && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
printf '\nCreated %s\n' "$output"
if $release; then
    echo 'Developer ID-signed, notarized, and stapled.'
else
    echo 'Locally signed; not Developer ID-signed or notarized.'
fi
