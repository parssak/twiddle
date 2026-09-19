#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

case "${1:-}" in
    '') package_mode=--release ;;
    --resume) package_mode=--resume-notarization ;;
    *) echo 'Usage: bash scripts/release.sh [--resume]' >&2; exit 1 ;;
esac

export TWIDDLE_SIGN_IDENTITY=${TWIDDLE_SIGN_IDENTITY:-'Developer ID Application: Parssa Kyanzadeh (3B8S7SSNL8)'}
export TWIDDLE_NOTARY_PROFILE=${TWIDDLE_NOTARY_PROFILE:-twiddle-notary}
export TWIDDLE_SIGN_KEYCHAIN=${TWIDDLE_SIGN_KEYCHAIN:-"$HOME/Library/Keychains/twiddle-release-signing-v3.keychain-db"}
password_file=${TWIDDLE_SIGN_KEYCHAIN_PASSWORD_FILE:-"$HOME/Library/Application Support/Twiddle/ReleaseSigning/keychain-password-v3"}

if [[ "$package_mode" == --release ]]; then
    [[ -f "$TWIDDLE_SIGN_KEYCHAIN" ]] || { echo "Signing keychain not found: $TWIDDLE_SIGN_KEYCHAIN" >&2; exit 1; }
    [[ -f "$password_file" ]] || { echo "Signing keychain password file not found: $password_file" >&2; exit 1; }
    [[ "$(stat -f '%Lp' "$password_file")" == 600 ]] || {
        echo "Signing keychain password file must have mode 600: $password_file" >&2
        exit 1
    }
    signing_password=$(<"$password_file")
    security unlock-keychain -p "$signing_password" "$TWIDDLE_SIGN_KEYCHAIN"
fi

bash package.sh "$package_mode"
