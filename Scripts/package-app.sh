#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CERT_NAME="SwitcherSilicon CodeSign"
BIN_NAME="SwitcherSilicon"
BUILD_APP="build/SwitcherSilicon.app"
INSTALL_APP="/Applications/SwitcherSilicon.app"

swift build -c release --arch arm64

# SwiftPM may put products under .build/release or .build/<triple>/release
RELEASE_DIR=""
for candidate in \
  ".build/arm64-apple-macosx/release" \
  ".build/release"
do
  if [[ -x "${candidate}/${BIN_NAME}" ]]; then
    RELEASE_DIR="$candidate"
    break
  fi
done
if [[ -z "$RELEASE_DIR" ]]; then
  echo "ERROR: release binary not found" >&2
  exit 1
fi
BIN="${RELEASE_DIR}/${BIN_NAME}"

rm -rf "$BUILD_APP"
mkdir -p "$BUILD_APP/Contents/MacOS" "$BUILD_APP/Contents/Resources"
cp "$BIN" "$BUILD_APP/Contents/MacOS/${BIN_NAME}"
cp Resources/Info.plist "$BUILD_APP/Contents/Info.plist"
printf 'APPL????' > "$BUILD_APP/Contents/PkgInfo"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$BUILD_APP/Contents/Resources/AppIcon.icns"
fi

# Dictionaries for Bundle.main (avoid copying SPM *.bundle — codesign rejects them).
if [[ -d Sources/Engine/Resources/Dictionaries ]]; then
  mkdir -p "$BUILD_APP/Contents/Resources/Dictionaries"
  cp -f Sources/Engine/Resources/Dictionaries/*.txt.gz \
        Sources/Engine/Resources/Dictionaries/NOTICE.md \
        "$BUILD_APP/Contents/Resources/Dictionaries/"
  echo "Dictionaries: $(du -sh "$BUILD_APP/Contents/Resources/Dictionaries" | awk '{print $1}')"
fi

# Strip Finder resource-forks / xattrs that break codesign
clean_for_sign() {
  local app="$1"
  xattr -cr "$app" 2>/dev/null || true
  find "$app" -name 'Icon' -delete 2>/dev/null || true
  find "$app" -name '.DS_Store' -delete 2>/dev/null || true
}

sign_app() {
  local app="$1"
  clean_for_sign "$app"
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
rm -rf "$INSTALL_APP"
ditto "$BUILD_APP" "$INSTALL_APP"
sign_app "$INSTALL_APP"

# Refresh LaunchServices so Finder picks up the new icon
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$INSTALL_APP" 2>/dev/null || true

echo "Built $BUILD_APP"
echo "Installed $INSTALL_APP"
codesign -dv "$INSTALL_APP" 2>&1 | grep -E 'Identifier|Signature|TeamIdentifier|Authority' || true
file "$INSTALL_APP/Contents/MacOS/${BIN_NAME}"
ls -lh "$INSTALL_APP/Contents/Resources/AppIcon.icns" 2>/dev/null || echo "WARNING: no AppIcon.icns"
