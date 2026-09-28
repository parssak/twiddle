#!/bin/bash
set -euo pipefail

signing_dir="$HOME/Library/Application Support/Twiddle/ReleaseSigning"
keychain="$HOME/Library/Keychains/twiddle-release-2026.keychain-db"
password_file="$signing_dir/release-keychain-password"
private_key="$signing_dir/developer-id-2026.key"
certificate="$signing_dir/developer-id-2026.cer"

[[ -f "$private_key" && -f "$certificate" ]] || {
    echo 'Developer ID key or certificate backup is missing.' >&2
    exit 1
}
if [[ -e "$keychain" || -e "$password_file" ]]; then
    [[ -f "$keychain" && -f "$password_file" ]] || {
        echo 'Release keychain and password file must both exist to resume setup.' >&2
        exit 1
    }
    [[ "$(stat -f '%Lp' "$password_file")" == 600 ]] || {
        echo 'Release keychain password file must have mode 600.' >&2
        exit 1
    }
fi

umask 077
mkdir -p "$signing_dir"
if [[ ! -e "$password_file" ]]; then openssl rand -base64 36 > "$password_file"; fi
password=$(<"$password_file")
if [[ ! -e "$keychain" ]]; then security create-keychain -p "$password" "$keychain"; fi
security unlock-keychain -p "$password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
temp_dir=$(mktemp -d)
trap 'rm -rf "$temp_dir"' EXIT
openssl x509 -inform DER -in "$certificate" -out "$temp_dir/certificate.pem"
openssl pkcs12 -export -inkey "$private_key" -in "$temp_dir/certificate.pem" \
    -out "$temp_dir/identity.p12" -passout "file:$password_file"
security import "$temp_dir/identity.p12" -k "$keychain" -f pkcs12 -P "$password" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -t private -k "$password" "$keychain" >/dev/null
security find-identity -v -p codesigning "$keychain"
echo "Release keychain ready: $keychain"
