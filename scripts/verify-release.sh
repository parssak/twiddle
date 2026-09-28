#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
appcast="$PWD/site/appcast-v2.xml"
dmg=${1:-"$PWD/build/Twiddle-$version-arm64.dmg"}
dmg=$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")
[[ -f "$dmg" && -f "$dmg.sha256" && -f "$appcast" ]] || {
    echo 'DMG, checksum, or appcast is missing.' >&2
    exit 1
}

(cd "$(dirname "$dmg")" && shasum -a 256 -c "$(basename "$dmg").sha256")
xcrun stapler validate "$dmg"
spctl --assess --type open --context context:primary-signature "$dmg"

mountpoint=$(mktemp -d "$PWD/build/.verify-release.XXXXXX")
cleanup() {
    hdiutil detach "$mountpoint" -quiet >/dev/null 2>&1 || true
    rmdir "$mountpoint" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "$mountpoint" "$dmg" >/dev/null

[[ -d "$mountpoint/Twiddle.app" && -L "$mountpoint/Applications" ]]
cmp "$PWD/Assets/DMG/.background.png" "$mountpoint/.background.png"
cmp "$PWD/Assets/DMG/.DS_Store" "$mountpoint/.DS_Store"
codesign --verify --deep --strict "$mountpoint/Twiddle.app"
spctl --assess --type execute "$mountpoint/Twiddle.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$mountpoint/Twiddle.app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$mountpoint/Twiddle.app/Contents/Info.plist")" == 'https://twiddle.fun/appcast-v2.xml' ]]

/usr/bin/python3 - "$appcast" "$dmg" "$version" <<'PY'
import os
import sys
import xml.etree.ElementTree as ET

appcast, dmg, version = sys.argv[1:]
sparkle = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
item = ET.parse(appcast).find('./channel/item')
assert item is not None, 'Missing appcast item'
assert item.findtext(sparkle + 'shortVersionString') == version, 'Appcast version mismatch'
enclosure = item.find('enclosure')
assert enclosure is not None, 'Missing appcast enclosure'
expected_url = f'https://github.com/parssak/twiddle/releases/download/v{version}/{os.path.basename(dmg)}'
assert enclosure.attrib.get('url') == expected_url, 'Appcast download URL mismatch'
assert int(enclosure.attrib.get('length', -1)) == os.path.getsize(dmg), 'Appcast size mismatch'
assert enclosure.attrib.get(sparkle + 'edSignature'), 'Missing Sparkle update signature'
PY
echo "Verified public-release candidate: $dmg"
