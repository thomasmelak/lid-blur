#!/bin/bash
# Creates a self-signed code signing certificate for Lid Blur and stores it as the GitHub
# Actions secrets used by the CI and Release workflows. Builds signed with the same certificate
# keep macOS privacy permissions (Screen Recording) across updates; ad hoc builds do not.
#
# Run once on a Mac with the GitHub CLI signed in:   scripts/make-signing-cert.sh
# Without gh, it prints the two secret values to add by hand instead.
#   MACOS_SIGNING_CERT           base64 of the .p12
#   MACOS_SIGNING_CERT_PASSWORD  its password
set -euo pipefail

NAME="Lid Blur Self-Signed"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
CNF

openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
    -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/cert.cnf" 2>/dev/null

PASSWORD="$(openssl rand -hex 16)"
# OpenSSL 3 defaults to a .p12 format the macOS keychain cannot read; -legacy keeps it compatible.
LEGACY=()
if openssl version | grep -q '^OpenSSL 3'; then LEGACY=(-legacy); fi
openssl pkcs12 -export "${LEGACY[@]+"${LEGACY[@]}"}" -name "$NAME" \
    -inkey "$WORK/key.pem" -in "$WORK/cert.pem" -out "$WORK/cert.p12" -passout "pass:$PASSWORD"

CERT_B64="$(base64 < "$WORK/cert.p12" | tr -d '\n')"

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    printf '%s' "$CERT_B64" | gh secret set MACOS_SIGNING_CERT
    printf '%s' "$PASSWORD" | gh secret set MACOS_SIGNING_CERT_PASSWORD
    echo "Stored MACOS_SIGNING_CERT and MACOS_SIGNING_CERT_PASSWORD for this repository."
else
    echo "Add these as repository secrets (Settings > Secrets and variables > Actions):"
    echo
    echo "MACOS_SIGNING_CERT:"
    echo "$CERT_B64"
    echo
    echo "MACOS_SIGNING_CERT_PASSWORD:"
    echo "$PASSWORD"
fi
