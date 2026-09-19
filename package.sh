#!/bin/bash
# With --release, sign and notarize using credentials already in Keychain.
set -euo pipefail
cd "$(dirname "$0")"
release=false
resume=false
case "${1:-}" in
    '') unset TWIDDLE_SIGN_IDENTITY ;;
    --release)
        release=true
        : "${TWIDDLE_SIGN_IDENTITY:?Set the Developer ID Application signing identity}"
        : "${TWIDDLE_NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
        export TWIDDLE_SIGN_IDENTITY
        ;;
    --resume-notarization)
        release=true
        resume=true
        : "${TWIDDLE_NOTARY_PROFILE:?Set the notarytool Keychain profile name}"
        ;;
    *) echo 'Usage: bash package.sh [--release|--resume-notarization]' >&2; exit 1 ;;
esac

generate_appcast() {
    local output=$1 version=$2 appcast_dir sparkle_root sparkle_key_file notes
    local -a appcast_key
    notes="$PWD/docs/releases/$version.md"
    [[ -f "$notes" ]] || { echo "Missing release notes: $notes" >&2; exit 1; }
    sparkle_root=$(bash scripts/prepare-sparkle.sh)
    appcast_dir=$(mktemp -d "$PWD/build/.appcast.XXXXXX")
    ditto "$output" "$appcast_dir/$(basename "$output")"
    cp "$notes" "$appcast_dir/$(basename "${output%.dmg}").md"
    if [[ -f "$PWD/site/appcast.xml" ]]; then cp "$PWD/site/appcast.xml" "$appcast_dir/appcast.xml"; fi
    sparkle_key_file=${TWIDDLE_SPARKLE_PRIVATE_KEY_FILE:-"$HOME/Library/Application Support/Twiddle/ReleaseSigning/sparkle-ed25519-private-key"}
    appcast_key=(--account com.parssa.twiddle)
    if [[ -f "$sparkle_key_file" ]]; then appcast_key=(--ed-key-file "$sparkle_key_file"); fi
    "$sparkle_root/bin/generate_appcast" "${appcast_key[@]}" \
        --download-url-prefix "https://github.com/parssak/twiddle/releases/download/v$version/" \
        --link "https://twiddle.fun" --embed-release-notes --maximum-versions 3 --maximum-deltas 0 \
        "$appcast_dir"
    cp "$appcast_dir/appcast.xml" "$PWD/site/appcast.xml"
    rm -rf "$appcast_dir"
}

finish_release() {
    local output=$1 version=$2
    (cd build && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
    generate_appcast "$output" "$version"
    printf '\nCreated %s\n' "$output"
    echo 'Developer ID-signed, notarized, and stapled.'
}

if $resume; then
    pending_images=()
    while IFS= read -r pending_image; do pending_images+=("$pending_image"); done \
        < <(find "$PWD/build" -maxdepth 1 -type f -name 'Twiddle-*.notarizing.dmg' -print)
    [[ ${#pending_images[@]} -eq 1 ]] || {
        echo "Expected exactly one resumable DMG in $PWD/build; found ${#pending_images[@]}." >&2
        exit 1
    }
    pending=${pending_images[0]}
    output=${pending%.notarizing.dmg}.dmg
    version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
    bash scripts/notarize-dmg.sh "$pending" "$output" "$TWIDDLE_NOTARY_PROFILE"
    finish_release "$output" "$version"
    exit 0
fi

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
codesign --verify --deep --strict "$staging/contents/Twiddle.app"
hdiutil create -volname Twiddle -srcfolder "$staging/contents" \
    -fs HFS+ -format UDZO "$staging/Twiddle.dmg"
hdiutil verify "$staging/Twiddle.dmg"
if $release; then
    codesign --timestamp --sign "$TWIDDLE_SIGN_IDENTITY" "$staging/Twiddle.dmg"
    pending="${output%.dmg}.notarizing.dmg"
    [[ ! -e "$pending" ]] || { echo "A resumable notarization already exists: $pending" >&2; exit 1; }
    mv "$staging/Twiddle.dmg" "$pending"
    bash scripts/notarize-dmg.sh "$pending" "$output" "$TWIDDLE_NOTARY_PROFILE"
else
    mv "$staging/Twiddle.dmg" "$output"
fi
if $release; then
    finish_release "$output" "$version"
else
    (cd build && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
    printf '\nCreated %s\n' "$output"
    echo 'Locally signed; not Developer ID-signed or notarized.'
fi
