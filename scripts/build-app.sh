#!/bin/bash
# Builds "Lid Blur.app" and build/LidBlur.zip.
#   UNIVERSAL=1   build for both Apple silicon and Intel (needs full Xcode)
#   VERSION=x.y.z override the version in the VERSION file
#   SIGN_IDENTITY  code signing identity (name or SHA-1). Defaults to the
#                  "Lid Blur Self-Signed" certificate when it is in the keychain,
#                  otherwise ad hoc ("-").
#                  A stable identity keeps privacy permissions (Screen Recording)
#                  across builds; see scripts/make-signing-cert.sh.
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

echo "==> Building the app icon"
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
        | awk '/"Lid Blur Self-Signed"/ {print $2; exit}')"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "==> Signing (ad hoc)"
else
    echo "==> Signing with $SIGN_IDENTITY"
fi
codesign --force --deep --options runtime --timestamp=none \
    --identifier com.thomasmelak.LidBlur --sign "$SIGN_IDENTITY" "$APP"

echo "==> Zipping"
rm -f "$BUILD_DIR/LidBlur.zip"
(cd "$BUILD_DIR" && ditto -c -k --keepParent "$APP_NAME" LidBlur.zip)

echo "==> Done: $APP"
