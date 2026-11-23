#!/bin/bash
# Builds "Lid Blur.app" and build/LidBlur.zip.
#   UNIVERSAL=1   build for both Apple silicon and Intel (needs full Xcode)
#   VERSION=x.y.z override the version in the VERSION file
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat VERSION)}"
VERSION="${VERSION#v}"
APP_NAME="Lid Blur.app"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME"

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> Compiling (release)"
swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}" --show-bin-path)"

echo "==> Assembling $APP_NAME $VERSION"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LidBlur" "$APP/Contents/MacOS/LidBlur"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Signing (ad hoc)"
codesign --force --deep --sign - "$APP"

echo "==> Zipping"
rm -f "$BUILD_DIR/LidBlur.zip"
(cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME" LidBlur.zip)

echo "==> Done: $APP"
