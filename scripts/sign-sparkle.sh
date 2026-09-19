#!/bin/bash
set -euo pipefail

app=${1:?Usage: bash scripts/sign-sparkle.sh APP_PATH SIGNING_IDENTITY}
identity=${2:?Usage: bash scripts/sign-sparkle.sh APP_PATH SIGNING_IDENTITY}
framework="$app/Contents/Frameworks/Sparkle.framework"
versioned="$framework/Versions/B"
[[ -d "$versioned" ]] || { echo "Sparkle framework is missing from $app" >&2; exit 1; }

sign=(codesign --force --sign "$identity" --options runtime)
if [[ -n "${TWIDDLE_SIGN_KEYCHAIN:-}" ]]; then
    sign+=(--keychain "$TWIDDLE_SIGN_KEYCHAIN")
fi
if [[ "${TWIDDLE_SIGN_TIMESTAMP:-secure}" == none ]]; then
    sign+=(--timestamp=none)
else
    sign+=(--timestamp)
fi

"${sign[@]}" "$versioned/XPCServices/Installer.xpc"
"${sign[@]}" --preserve-metadata=entitlements "$versioned/XPCServices/Downloader.xpc"
"${sign[@]}" "$versioned/Autoupdate"
"${sign[@]}" "$versioned/Updater.app"
"${sign[@]}" "$framework"
codesign --verify --deep --strict "$framework"
