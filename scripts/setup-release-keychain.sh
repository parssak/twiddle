#!/bin/bash
set +x
set -euo pipefail
source "$(dirname "$0")/release-identity.sh"

signing_dir="$HOME/Library/Application Support/Twiddle/ReleaseSigning"
default_keychain="$HOME/Library/Keychains/twiddle-release-2026.keychain-db"
if [[ -f "$signing_dir/release-keychain-path" ]]; then
    IFS= read -r default_keychain < "$signing_dir/release-keychain-path"
fi
keychain=${TWIDDLE_SIGN_KEYCHAIN:-"$default_keychain"}
password_file="$signing_dir/release-keychain-password"
private_key="$signing_dir/developer-id-2026.key"
certificate="$signing_dir/developer-id-2026.cer"

[[ -f "$private_key" && -f "$certificate" ]] || {
    echo 'Developer ID key or certificate backup is missing.' >&2
    exit 1
}
[[ "$(stat -f '%Lp' "$private_key")" == 600 ]] || {
    echo 'Developer ID private-key backup must have mode 600.' >&2
    exit 1
}
fingerprint=$(openssl x509 -inform DER -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
[[ "$fingerprint" == "$release_certificate_sha1" ]] || {
    echo 'Certificate differs from the pinned release identity; refusing to configure it.' >&2
    exit 1
}
if [[ -e "$keychain" && ! -f "$password_file" ]]; then
    echo 'The existing release keychain needs its saved password; refusing to replace it.' >&2
    exit 1
fi
if [[ -e "$password_file" ]]; then
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
printf '%s\n' "$keychain" > "$signing_dir/release-keychain-path"
chmod 600 "$signing_dir/release-keychain-path"
echo "Release keychain ready: $keychain"
