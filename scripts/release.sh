#!/bin/bash
set +x
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
source scripts/release-identity.sh

case "${1:-}" in
    '') package_mode=--release ;;
    --resume) package_mode=--resume-notarization ;;
    --check-signing) package_mode=--check-signing ;;
    *) echo 'Usage: bash scripts/release.sh [--resume|--check-signing]' >&2; exit 1 ;;
esac

export TWIDDLE_SIGN_IDENTITY=${TWIDDLE_SIGN_IDENTITY:-"$release_identity"}
export TWIDDLE_NOTARY_PROFILE=${TWIDDLE_NOTARY_PROFILE:-twiddle-notary}
signing_dir="$HOME/Library/Application Support/Twiddle/ReleaseSigning"
default_keychain="$HOME/Library/Keychains/twiddle-release-2026.keychain-db"
if [[ -f "$signing_dir/release-keychain-path" ]]; then
    IFS= read -r default_keychain < "$signing_dir/release-keychain-path"
fi
export TWIDDLE_SIGN_KEYCHAIN=${TWIDDLE_SIGN_KEYCHAIN:-"$default_keychain"}
password_file=${TWIDDLE_SIGN_KEYCHAIN_PASSWORD_FILE:-"$HOME/Library/Application Support/Twiddle/ReleaseSigning/release-keychain-password"}
developer_key_backup=${TWIDDLE_DEVELOPER_KEY_BACKUP_FILE:-"$HOME/Library/Application Support/Twiddle/ReleaseSigning/developer-id-2026.key"}
developer_certificate=${TWIDDLE_DEVELOPER_CERTIFICATE_FILE:-"$HOME/Library/Application Support/Twiddle/ReleaseSigning/developer-id-2026.cer"}
sparkle_key_backup=${TWIDDLE_SPARKLE_PRIVATE_KEY_FILE:-"$HOME/Library/Application Support/Twiddle/ReleaseSigning/sparkle-ed25519-v2-private-key"}

{
    [[ -f "$TWIDDLE_SIGN_KEYCHAIN" ]] || { echo "Signing keychain not found: $TWIDDLE_SIGN_KEYCHAIN" >&2; exit 1; }
    for backup in "$developer_key_backup" "$sparkle_key_backup"; do
        [[ -f "$backup" ]] || { echo "Release key backup not found: $backup" >&2; exit 1; }
        [[ "$(stat -f '%Lp' "$backup")" == 600 ]] || {
            echo "Release key backup must have mode 600: $backup" >&2
            exit 1
        }
    done
    [[ -f "$password_file" ]] || { echo "Signing keychain password file not found: $password_file" >&2; exit 1; }
    [[ "$(stat -f '%Lp' "$password_file")" == 600 ]] || {
        echo "Signing keychain password file must have mode 600: $password_file" >&2
        exit 1
    }
    [[ -f "$developer_certificate" ]] || { echo 'Developer ID certificate backup is missing.' >&2; exit 1; }
    check_dir=$(mktemp -d)
    trap 'rm -rf "$check_dir"' EXIT
    openssl pkey -in "$developer_key_backup" -pubout -outform DER > "$check_dir/key-public.der"
    openssl x509 -inform DER -in "$developer_certificate" -pubkey -noout |
        openssl pkey -pubin -outform DER > "$check_dir/certificate-public.der"
    cmp -s "$check_dir/key-public.der" "$check_dir/certificate-public.der" || {
        echo 'Developer ID private key and certificate do not match; restore the existing pair.' >&2
        exit 1
    }
    fingerprint=$(openssl x509 -inform DER -in "$developer_certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
    [[ "$fingerprint" == "$release_certificate_sha1" ]] || {
        echo 'Developer ID certificate differs from the pinned release identity; restore the existing certificate.' >&2
        exit 1
    }
    [[ "$TWIDDLE_SIGN_IDENTITY" == "$release_identity" || "$TWIDDLE_SIGN_IDENTITY" == "$fingerprint" ]] || {
        echo 'Requested signing identity differs from the pinned release identity.' >&2
        exit 1
    }
    swift scripts/verify-sparkle.swift --check-key "$sparkle_key_backup" Info.plist
    signing_password=$(<"$password_file")
    if ! security unlock-keychain -p "$signing_password" "$TWIDDLE_SIGN_KEYCHAIN"; then
        echo 'Saved password cannot unlock the selected release keychain. Preserve it and restore access using the existing key and certificate.' >&2
        exit 1
    fi
    unset signing_password
    security find-identity -v -p codesigning "$TWIDDLE_SIGN_KEYCHAIN" | grep -q "$fingerprint" || {
        echo 'Selected keychain does not contain the backed-up Developer ID identity.' >&2
        exit 1
    }
    export TWIDDLE_SIGN_IDENTITY="$fingerprint"
    echo 'Release signing preflight passed: existing Developer ID and Sparkle identities verified.'
    [[ "$package_mode" != --check-signing ]] || exit 0
}

bash package.sh "$package_mode"
bash scripts/verify-release.sh
