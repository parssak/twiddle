#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
bash build.sh

destination=/Applications/Lowpasser.app
staging=$(mktemp -d /Applications/.lowpasser.XXXXXX)
trap 'rm -rf "$staging"' EXIT
ditto build/Lowpasser.app "$staging/Lowpasser.app"
codesign --verify --strict "$staging/Lowpasser.app"
if [[ -e "$destination" ]]; then mv "$destination" "$staging/previous.app"; fi
if ! mv "$staging/Lowpasser.app" "$destination"; then
    if [[ -e "$staging/previous.app" ]]; then mv "$staging/previous.app" "$destination"; fi
    exit 1
fi
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$destination"
mdimport "$destination"
printf '\nInstalled %s\nQuit any running copy, then run: open "%s"\n' "$destination" "$destination"
