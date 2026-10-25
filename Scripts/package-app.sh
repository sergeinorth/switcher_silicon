#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN=".build/release/SwitcherSilicon"
BUILD_APP="build/SwitcherSilicon.app"
INSTALL_APP="/Applications/SwitcherSilicon.app"

rm -rf "$BUILD_APP"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
cp "$BIN" "$BUILD_APP/Contents/MacOS/SwitcherSilicon"
cp Resources/Info.plist "$BUILD_APP/Contents/Info.plist"
printf 'APPL????' > "$BUILD_APP/Contents/PkgInfo"

codesign --force --sign - --entitlements Resources/SwitcherSilicon.entitlements "$BUILD_APP" 2>/dev/null \
  || codesign --force --sign - "$BUILD_APP"

# Stable path for Accessibility TCC — avoid Desktop rebuild path churn.
pkill -f 'SwitcherSilicon.app/Contents/MacOS/SwitcherSilicon' 2>/dev/null || true
sleep 0.3
rm -rf "$INSTALL_APP"
cp -R "$BUILD_APP" "$INSTALL_APP"
codesign --force --sign - "$INSTALL_APP" 2>/dev/null || true
xattr -cr "$INSTALL_APP" 2>/dev/null || true

echo "Built $BUILD_APP"
echo "Installed $INSTALL_APP"
file "$INSTALL_APP/Contents/MacOS/SwitcherSilicon"
