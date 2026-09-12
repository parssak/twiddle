#!/bin/bash
# One persistent local identity. Never fall back to ad-hoc signing.
set +x
set -euo pipefail
umask 077

app=${1:?Usage: bash scripts/sign-app.sh /path/to/Lowpasser.app}
signing_dir="$HOME/Library/Application Support/Lowpasser/Signing"
signing_keychain="$HOME/Library/Keychains/lowpasser-local-signing.keychain-db"
certificate="$signing_dir/certificate.pem"
password_file="$signing_dir/keychain-password"

if [[ ! -f "$certificate" ]]; then
    if [[ -e "$signing_keychain" || -e "$password_file" ]]; then
        echo "Incomplete Lowpasser signing setup in $signing_dir; refusing to replace its identity." >&2
        exit 1
    fi
    mkdir -p "$signing_dir"
    chmod 700 "$signing_dir"
    temporary=$(mktemp -d "$signing_dir/setup.XXXXXX")
    trap 'rm -rf "$temporary"' EXIT
    /usr/bin/openssl rand -base64 32 > "$password_file"
    IFS= read -r signing_password < "$password_file"
    security create-keychain -p "$signing_password" "$signing_keychain"
    security set-keychain-settings -lut 21600 "$signing_keychain"
    security unlock-keychain -p "$signing_password" "$signing_keychain"
    cat > "$temporary/certificate.cnf" <<'CONFIG'
[req]
prompt = no
distinguished_name = subject
x509_extensions = code_signing
[subject]
CN = Lowpasser Local Development
[code_signing]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
CONFIG
    /usr/bin/openssl req -new -newkey rsa:2048 -nodes -x509 -sha256 -days 3650 \
        -config "$temporary/certificate.cnf" -keyout "$temporary/private-key.pem" \
        -out "$certificate" 2> "$temporary/openssl.log"
    /usr/bin/openssl rand -base64 32 > "$temporary/transfer-password"
    /usr/bin/openssl pkcs12 -export -inkey "$temporary/private-key.pem" -in "$certificate" \
        -name "Lowpasser Local Development" -out "$temporary/identity.p12" \
        -passout "file:$temporary/transfer-password"
    IFS= read -r transfer_password < "$temporary/transfer-password"
    security import "$temporary/identity.p12" -k "$signing_keychain" -f pkcs12 \
        -P "$transfer_password" -x -T /usr/bin/codesign
    security set-key-partition-list -S 'apple-tool:,apple:,codesign:' -s \
        -k "$signing_password" "$signing_keychain" > /dev/null
    unset transfer_password signing_password
fi

if [[ ! -f "$password_file" || ! -f "$signing_keychain" ]]; then
    echo "Lowpasser's existing signing keychain is missing. Restore it; do not generate a replacement." >&2
    exit 1
fi
IFS= read -r signing_password < "$password_file"
security unlock-keychain -p "$signing_password" "$signing_keychain"
unset signing_password
# codesign still needs the keychain in the user search list even with --keychain.
# Preserve every existing entry and leave the default keychain unchanged.
/usr/bin/python3 - "$signing_keychain" <<'PY'
import shlex
import subprocess
import sys
security = '/usr/bin/security'
paths = shlex.split(subprocess.check_output([security, 'list-keychains', '-d', 'user'], text=True))
if sys.argv[1] not in paths:
    subprocess.run([security, 'list-keychains', '-d', 'user', '-s', *paths, sys.argv[1]], check=True)
PY
fingerprint=$(/usr/bin/openssl x509 -in "$certificate" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')
[[ "$fingerprint" =~ ^[0-9A-Fa-f]{40}$ ]] || { echo "Invalid signing certificate fingerprint." >&2; exit 1; }

# Trust only this local certificate for code signing, in the current user's
# trust store. This is not an SSL trust root or a system-wide trust change.
if [[ ! -f "$signing_dir/trust-configured" ]]; then
    security add-trusted-cert -r trustRoot -p codeSign -k "$signing_keychain" "$certificate"
    touch "$signing_dir/trust-configured"
fi

codesign --force --sign "$fingerprint" --keychain "$signing_keychain" --timestamp=none \
    --identifier com.parssa.lowpasser.poc \
    --requirements "=designated => identifier \"com.parssa.lowpasser.poc\" and certificate leaf = H\"$fingerprint\"" \
    "$app"
codesign --verify --strict --verbose=2 "$app"
