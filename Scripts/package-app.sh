#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CERT_NAME="SwitcherSilicon CodeSign"
BIN_NAME="SwitcherSilicon"
BUILD_APP="build/SwitcherSilicon.app"
INSTALL_APP="/Applications/SwitcherSilicon.app"

swift build -c release --arch arm64
BIN=".build/release/${BIN_NAME}"

rm -rf "$BUILD_APP"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
cp "$BIN" "$BUILD_APP/Contents/MacOS/${BIN_NAME}"
cp Resources/Info.plist "$BUILD_APP/Contents/Info.plist"
printf 'APPL????' > "$BUILD_APP/Contents/PkgInfo"

sign_app() {
  local app="$1"
  if security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    codesign --force --deep --sign "$CERT_NAME" "$app"
    echo "Signed with $CERT_NAME"
  else
    codesign --force --sign - "$app"
    echo "WARNING: signed ad-hoc (TCC will break on each rebuild)"
  fi
}

sign_app "$BUILD_APP"

pkill -f "${INSTALL_APP}/Contents/MacOS/${BIN_NAME}" 2>/dev/null || true
sleep 0.2
if [[ -d "$INSTALL_APP" ]]; then
  ditto "$BUILD_APP" "$INSTALL_APP"
else
  cp -R "$BUILD_APP" "$INSTALL_APP"
fi
sign_app "$INSTALL_APP"
xattr -cr "$INSTALL_APP" 2>/dev/null || true

echo "Built $BUILD_APP"
echo "Installed $INSTALL_APP"
codesign -dv "$INSTALL_APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier|Authority' || true
file "$INSTALL_APP/Contents/MacOS/${BIN_NAME}"
