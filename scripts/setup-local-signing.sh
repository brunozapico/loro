#!/bin/bash
# Create one persistent signing key. Never run this on ephemeral CI runners.
set -euo pipefail
umask 077
CONFIG_DIR="$HOME/Library/Application Support/Loro/Signing"
CONFIG="$CONFIG_DIR/identity"
if [ -f "$CONFIG" ]; then
    echo "Loro already has a persistent signing identity at $CONFIG"
    exit 0
fi
if [ -n "${CI:-}" ]; then echo 'Use a provisioned signing identity in CI.' >&2; exit 1; fi
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cat > "$WORK/certificate.cnf" <<'CONFIG'
[req]
distinguished_name = name
x509_extensions = signing
prompt = no
[name]
CN = Loro Local Signing
[signing]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONFIG
/usr/bin/openssl req -new -newkey rsa:3072 -nodes -x509 -days 3650 \
    -config "$WORK/certificate.cnf" -keyout "$WORK/key.pem" -out "$WORK/certificate.pem" 2>/dev/null
export LORO_IMPORT_PASSWORD="$(/usr/bin/openssl rand -hex 24)"
/usr/bin/openssl pkcs12 -export -inkey "$WORK/key.pem" -in "$WORK/certificate.pem" \
    -out "$WORK/identity.p12" -passout env:LORO_IMPORT_PASSWORD
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P "$LORO_IMPORT_PASSWORD" -T /usr/bin/codesign
FINGERPRINT="$(/usr/bin/openssl x509 -in "$WORK/certificate.pem" -noout -fingerprint -sha1 | cut -d= -f2 | tr -d ':')"
# Public certificate only; the private key remains in the login keychain.
mkdir -p "$CONFIG_DIR"
cp "$WORK/certificate.pem" "$CONFIG_DIR/certificate.pem"
printf '%s\n' "$FINGERPRINT" > "$CONFIG"
echo "Persistent identity saved to $CONFIG. Keep this keychain for future updates."
