#!/bin/bash
# CI helper: imports the self-signed certificate from MACOS_SIGNING_CERT (base64 .p12) and
# MACOS_SIGNING_CERT_PASSWORD into a temporary keychain and exports SIGN_IDENTITY for
# build-app.sh. Without the secrets the build stays ad hoc signed.
set -euo pipefail

if [ -z "${MACOS_SIGNING_CERT:-}" ]; then
    echo "No signing certificate configured; building ad hoc signed."
    exit 0
fi

KEYCHAIN="$RUNNER_TEMP/lidblur-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
P12="$RUNNER_TEMP/lidblur-signing.p12"

printf '%s' "$MACOS_SIGNING_CERT" | base64 --decode > "$P12"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings -lut 3600 "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security import "$P12" -k "$KEYCHAIN" -P "${MACOS_SIGNING_CERT_PASSWORD:-}" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
# Put the temporary keychain on the search list so codesign can find the identity.
security list-keychains -d user -s "$KEYCHAIN" $(security list-keychains -d user | tr -d '"')
rm -f "$P12"

# Sign by SHA-1 so an untrusted self-signed certificate can still be selected.
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/\)/ {print $2; exit}')"
if [ -z "$IDENTITY" ]; then
    echo "Could not find the signing identity in the imported certificate." >&2
    exit 1
fi
echo "SIGN_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "Signing with certificate $IDENTITY"
