#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh

destination=/Applications/Twiddle.app
staging=$(mktemp -d /Applications/.twiddle.XXXXXX)
trap 'rm -rf "$staging"' EXIT
ditto build/Twiddle.app "$staging/Twiddle.app"
codesign --verify --strict "$staging/Twiddle.app"
if [[ -e "$destination" ]]; then mv "$destination" "$staging/previous.app"; fi
if ! mv "$staging/Twiddle.app" "$destination"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$destination"; fi
    exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
mdimport "$destination"
printf '\nInstalled %s\nQuit any running copy, then run: open "%s"\n' "$destination" "$destination"
