#!/bin/bash
# Builds dist/MacBull.app (universal, hardened runtime, ad-hoc signed) and dist/MacBull.zip.
# Set MACBULL_SIGN_ID to a Developer ID identity to sign with it instead of ad hoc.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="MacBull"
DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"
SIGN_ID="${MACBULL_SIGN_ID:--}"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [[ ! "$VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    echo "VERSION must look like 1.2.3, found '$VERSION'" >&2
    exit 1
fi
# Build number derived from the version: 0.1.0 -> 100, 1.2.3 -> 10203.
BUILD_NUMBER=$(( BASH_REMATCH[1] * 10000 + BASH_REMATCH[2] * 100 + BASH_REMATCH[3] ))

echo "Building $APP_NAME $VERSION ($BUILD_NUMBER), arm64 and x86_64"
swift build -c release --arch arm64 --arch x86_64
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"

rm -rf "$APP" "$DIST/$APP_NAME.zip"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$APP_NAME" "$CONTENTS/MacOS/$APP_NAME"

cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
PLIST_BUDDY=/usr/libexec/PlistBuddy
"$PLIST_BUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$CONTENTS/Info.plist"
"$PLIST_BUDDY" -c "Set :CFBundleVersion $BUILD_NUMBER" "$CONTENTS/Info.plist"
plutil -lint "$CONTENTS/Info.plist" >/dev/null

# App icon: a ready .icns wins, otherwise build one from the 1024 px master.
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
    cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"
elif [[ -f "$ROOT/Resources/AppIcon.png" ]]; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    ICONSET="$WORK/AppIcon.iconset"
    mkdir -p "$ICONSET"
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
        double=$(( size * 2 ))
        sips -z "$double" "$double" "$ROOT/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
else
    echo "No Resources/AppIcon.icns or AppIcon.png, building without an icon" >&2
fi

# Notification sounds.
shopt -s nullglob
SOUNDS=("$ROOT"/Resources/Sounds/*.caf)
if (( ${#SOUNDS[@]} > 0 )); then
    mkdir -p "$CONTENTS/Resources/Sounds"
    cp "${SOUNDS[@]}" "$CONTENTS/Resources/Sounds/"
fi

echo "Signing with '${SIGN_ID}' (hardened runtime)"
codesign --force --options runtime --timestamp=none -s "$SIGN_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# No extended attributes, so the signature survives the zip.
ditto -c -k --norsrc --keepParent "$APP" "$DIST/$APP_NAME.zip"
echo "Built $APP and $DIST/$APP_NAME.zip"
