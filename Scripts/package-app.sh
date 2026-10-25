#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN=".build/release/SwitcherSilicon"
APP="build/SwitcherSilicon.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SwitcherSilicon"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ -d Sounds ]]; then
  cp -R Sounds/. "$APP/Contents/Resources/" 2>/dev/null || true
fi

codesign --force --sign - --entitlements Resources/SwitcherSilicon.entitlements "$APP" 2>/dev/null \
  || codesign --force --sign - "$APP"

echo "Built $APP"
file "$APP/Contents/MacOS/SwitcherSilicon"
