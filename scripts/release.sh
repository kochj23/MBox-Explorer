#!/usr/bin/env bash
#
# release.sh — build, sign (Developer ID), notarize, staple, and package MBox Explorer
# as a Gatekeeper-clean .dmg that end users can open with a simple drag-and-drop.
#
# One-time setup is documented in RELEASE.md:
#   1. A "Developer ID Application" certificate in your login keychain.
#   2. Notary credentials stored as a keychain profile named "$NOTARY_PROFILE":
#        xcrun notarytool store-credentials MBOX_NOTARY \
#          --apple-id "you@example.com" --team-id QRRCB8HB3W --password <app-specific-password>
#   3. The Metal Toolchain: xcodebuild -downloadComponent MetalToolchain
#
# Usage:  ./scripts/release.sh [version]     (version defaults to today's date)
#
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="MBox Explorer.xcodeproj"
SCHEME="${SCHEME:-MBox Explorer}"
CONFIG="${CONFIG:-Release}"
TEAM_ID="${TEAM_ID:-QRRCB8HB3W}"
NOTARY_PROFILE="${NOTARY_PROFILE:-MBOX_NOTARY}"
APP_NAME="MBox Explorer"
VERSION="${1:-$(date +%Y.%m.%d)}"

BUILD_DIR="$(pwd)/build"
ARCHIVE="$BUILD_DIR/${APP_NAME}.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/${APP_NAME// /-}-${VERSION}.dmg"

# ---- Preflight ---------------------------------------------------------------
echo "==> Preflight checks"
if ! security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  echo "ERROR: no 'Developer ID Application' certificate found (see RELEASE.md step 1)." >&2
  exit 1
fi
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "ERROR: notary profile '$NOTARY_PROFILE' not set up (see RELEASE.md step 2)." >&2
  exit 1
fi

rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"

# ---- Archive -----------------------------------------------------------------
echo "==> Archiving ($CONFIG)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration "$CONFIG" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" archive

# ---- Export (Developer ID signed) -------------------------------------------
echo "==> Exporting with Developer ID…"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "scripts/ExportOptions.plist"

APP="$EXPORT_DIR/${APP_NAME}.app"
[ -d "$APP" ] || { echo "ERROR: export failed — $APP not found." >&2; exit 1; }

# ---- Package DMG -------------------------------------------------------------
echo "==> Building DMG…"
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

# ---- Notarize + staple -------------------------------------------------------
echo "==> Notarizing (uploads to Apple and waits — usually a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling the notarization ticket…"
xcrun stapler staple "$DMG"

# ---- Verify ------------------------------------------------------------------
echo "==> Verifying…"
codesign --verify --deep --strict --verbose=2 "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG" || true

echo
echo "✅ Done: $DMG"
echo "   Upload this .dmg to a GitHub Release. It opens with no Gatekeeper prompt,"
echo "   even offline, because the notarization ticket is stapled."
