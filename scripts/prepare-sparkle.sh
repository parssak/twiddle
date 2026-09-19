#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=2.10.0
archive_sha256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
dependencies="$PWD/build/dependencies"
destination="$dependencies/Sparkle-$version"

if [[ -d "$destination/Sparkle.framework" && -x "$destination/bin/generate_appcast" ]]; then
    printf '%s\n' "$destination"
    exit 0
fi

mkdir -p "$dependencies"
staging=$(mktemp -d "$dependencies/.sparkle.XXXXXX")
cleanup() { rm -rf "$staging"; }
trap cleanup EXIT
archive="$staging/Sparkle-$version.tar.xz"
curl -fL --retry 3 --silent --show-error \
    -o "$archive" "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz"
printf '%s  %s\n' "$archive_sha256" "$archive" | shasum -a 256 -c - >/dev/null
tar -xJf "$archive" -C "$staging" \
    ./Sparkle.framework ./LICENSE ./bin/generate_appcast ./bin/generate_keys ./bin/sign_update
codesign --verify --strict "$staging/Sparkle.framework"
codesign --verify --strict "$staging/bin/generate_appcast"

candidate="$staging/Sparkle-$version"
mkdir "$candidate"
mv "$staging/Sparkle.framework" "$candidate/Sparkle.framework"
mv "$staging/bin" "$candidate/bin"
mv "$staging/LICENSE" "$candidate/LICENSE"
if [[ -e "$destination" ]]; then
    rm -rf "$destination"
fi
mv "$candidate" "$destination"
printf '%s\n' "$destination"
