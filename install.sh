#!/bin/bash
# Lid Blur installer.
#   curl -fsSL https://raw.githubusercontent.com/thomasmelak/lid-blur/main/install.sh | bash
set -euo pipefail

REPO="thomasmelak/lid-blur"
APP_NAME="Lid Blur.app"
ZIP_URL="https://github.com/$REPO/releases/latest/download/LidBlur.zip"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "Lid Blur only runs on macOS." >&2
    exit 1
fi

DEST="/Applications"
if [ ! -w "$DEST" ]; then
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading the latest release"
if curl -fsSL "$ZIP_URL" -o "$TMP/LidBlur.zip"; then
    ditto -x -k "$TMP/LidBlur.zip" "$TMP"
else
    echo "==> No release yet, building from source instead"
    if ! xcode-select -p >/dev/null 2>&1; then
        echo "Building needs the Xcode Command Line Tools. Install them with:" >&2
        echo "    xcode-select --install" >&2
        exit 1
    fi
    git clone --depth 1 "https://github.com/$REPO.git" "$TMP/src"
    "$TMP/src/scripts/build-app.sh"
    ditto "$TMP/src/build/$APP_NAME" "$TMP/$APP_NAME"
fi

if [ ! -d "$TMP/$APP_NAME" ]; then
    echo "Something went wrong: $APP_NAME was not found in the download." >&2
    exit 1
fi

echo "==> Installing to $DEST"
pkill -x LidBlur 2>/dev/null || true
rm -rf "${DEST:?}/$APP_NAME"
ditto "$TMP/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

echo "==> Starting Lid Blur"
open "$DEST/$APP_NAME"

echo
echo "Lid Blur is running. Look for the laptop icon in the menu bar."
echo "It starts automatically at login; turn that off from the menu if you like."
