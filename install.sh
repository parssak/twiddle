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

# A symlink keeps the CLI tied to whichever build is currently installed.
cli_dir="$HOME/.local/bin"
mkdir -p "$cli_dir"
if [[ ! -e "$cli_dir/twiddle" && ! -L "$cli_dir/twiddle" ]]; then
    ln -s "$destination/Contents/MacOS/Twiddle" "$cli_dir/twiddle"
    printf 'CLI installed: %s/twiddle\n' "$cli_dir"
elif [[ -L "$cli_dir/twiddle" && "$(readlink "$cli_dir/twiddle")" == "$destination/Contents/MacOS/Twiddle" ]]; then
    printf 'CLI updated: %s/twiddle\n' "$cli_dir"
else
    printf 'Existing %s/twiddle left unchanged; use the app executable with --cli.\n' "$cli_dir"
fi
