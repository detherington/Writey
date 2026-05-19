#!/bin/bash
#
# Build a release .app and wrap it in a DMG that you can copy to your other
# Macs. No code signing, no notarization, no Sparkle. The first time the
# DMG is opened on a different Mac, Gatekeeper will warn that the app is
# from an unidentified developer — right-click → Open once to bypass.
#
# Usage:
#   ./scripts/build-dmg.sh           # builds Writey-0.1.0.dmg (from project.yml MARKETING_VERSION)
#   ./scripts/build-dmg.sh 0.2.0     # overrides the version
#
set -euo pipefail

cd "$(dirname "$0")/.."

if [ ! -f "Sources/Writey/Sync/SyncConfig.swift" ]; then
  echo "❌ Sources/Writey/Sync/SyncConfig.swift is missing."
  echo "   Run:  cp Sources/Writey/Sync/SyncConfig.template.swift Sources/Writey/Sync/SyncConfig.swift"
  echo "   Then paste in your OAuth client ID + redirect scheme."
  exit 1
fi

VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)}"
DMG="Writey-${VERSION}.dmg"
BUILD_DIR="build"

echo "▸ xcodegen generate"
xcodegen generate

echo "▸ xcodebuild (Release, no signing)"
xcodebuild \
  -project Writey.xcodeproj \
  -scheme Writey \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  | tail -20

APP_PATH=$(find "$BUILD_DIR/Build/Products/Release" -maxdepth 2 -name "Writey.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
  echo "❌ Couldn't find built Writey.app"; exit 1
fi
echo "▸ Built: $APP_PATH"

STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG"
echo "▸ hdiutil create → $DMG"
hdiutil create \
  -srcfolder "$STAGING" \
  -volname "Writey" \
  -fs APFS \
  -format UDZO \
  -ov \
  "$DMG" \
  > /dev/null

rm -rf "$STAGING"

SIZE=$(du -h "$DMG" | cut -f1)
echo ""
echo "✅ $DMG ($SIZE)"
echo "   Copy this file to your other Macs (AirDrop / iCloud Drive / scp)."
echo "   First time: right-click the app in Finder → Open to bypass Gatekeeper."
