#!/bin/bash
# Packages build/Lid Blur.app into build/LidBlur.dmg with a drag-to-Applications layout.
# Run scripts/build-app.sh first.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Lid Blur.app"
DMG="build/LidBlur.dmg"
STAGING="build/dmg"

if [ ! -d "$APP" ]; then
    echo "Missing $APP. Run scripts/build-app.sh first." >&2
    exit 1
fi

echo "==> Staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$APP" "$STAGING/Lid Blur.app"
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG"
hdiutil create -volname "Lid Blur" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

echo "==> Done: $DMG"
