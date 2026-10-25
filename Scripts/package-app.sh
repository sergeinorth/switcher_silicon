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

# Update in place (avoid rm -rf of the authorized app when possible).
pkill -f 'SwitcherSilicon.app/Contents/MacOS/SwitcherSilicon' 2>/dev/null || true
sleep 0.2
if [[ -d "$INSTALL_APP" ]]; then
  ditto "$BUILD_APP" "$INSTALL_APP"
else
  cp -R "$BUILD_APP" "$INSTALL_APP"
fi
codesign --force --sign - "$INSTALL_APP" 2>/dev/null || true
xattr -cr "$INSTALL_APP" 2>/dev/null || true

echo "Built $BUILD_APP"
echo "Installed $INSTALL_APP"
echo "NOTE: After each new binary, re-toggle Accessibility + Input Monitoring if icon shows !"
file "$INSTALL_APP/Contents/MacOS/SwitcherSilicon"
