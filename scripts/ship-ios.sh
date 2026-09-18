#!/bin/bash
#
# One-shot: bump build number, archive Writey-iOS, export .ipa,
# upload to App Store Connect via TestFlight, copy archive to
# Xcode Organizer's default location.
#
# Auth: App Store Connect API key stored at
#   ~/.appstoreconnect/private_keys/AuthKey_CQU2C4W2SM.p8
# with the credentials configured below. The Issuer ID is a per-team
# public identifier (not secret); the .p8 is private but lives outside
# the repo.
#
# Usage:
#   ./scripts/ship-ios.sh              # bumps CURRENT_PROJECT_VERSION and ships
#   ./scripts/ship-ios.sh --no-bump    # ships current build number as-is
#
set -euo pipefail

cd "$(dirname "$0")/.."

# --- credentials -------------------------------------------------------
ASC_KEY_ID="CQU2C4W2SM"
ASC_ISSUER_ID="f50d1055-f6d4-4641-819a-447211b6b6c1"
ASC_KEY_PATH="$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8"

if [ ! -f "$ASC_KEY_PATH" ]; then
  echo "❌ App Store Connect API key not found at $ASC_KEY_PATH"
  echo "   Re-generate at https://appstoreconnect.apple.com/access/api"
  echo "   and copy the .p8 there."
  exit 1
fi

# --- pre-flight sanity checks -----------------------------------------
if [ ! -f "Sources/Writey/Core/Sync/SyncConfig.swift" ]; then
  echo "❌ Sources/Writey/Core/Sync/SyncConfig.swift is missing."
  echo "   cp Sources/Writey/Core/Sync/SyncConfig.template.swift Sources/Writey/Core/Sync/SyncConfig.swift"
  exit 1
fi

# --- bump build number (default) --------------------------------------
if [ "${1:-}" != "--no-bump" ]; then
  CUR=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
  NEW=$((CUR + 1))
  echo "▸ Bumping CURRENT_PROJECT_VERSION: $CUR → $NEW"
  /usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CUR\"/CURRENT_PROJECT_VERSION: \"$NEW\"/" project.yml
fi

VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
echo "▸ Shipping Writey-iOS $VERSION ($BUILD)"

# --- regenerate + archive ---------------------------------------------
echo "▸ xcodegen generate"
xcodegen generate | tail -1

echo "▸ archive (this takes ~1 min)"
rm -rf build/Writey-iOS.xcarchive build/Writey-iOS-export
xcodebuild archive \
  -project Writey.xcodeproj \
  -scheme Writey-iOS \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/Writey-iOS.xcarchive \
  -allowProvisioningUpdates \
  | tail -3

if [ ! -d build/Writey-iOS.xcarchive ]; then
  echo "❌ Archive not produced — check xcodebuild output above"; exit 1
fi

# --- export ------------------------------------------------------------
echo "▸ export .ipa (App Store distribution)"
xcodebuild -exportArchive \
  -archivePath build/Writey-iOS.xcarchive \
  -exportPath build/Writey-iOS-export \
  -exportOptionsPlist build/ExportOptions.plist \
  -allowProvisioningUpdates \
  | tail -2

IPA=build/Writey-iOS-export/Writey.ipa
if [ ! -f "$IPA" ]; then
  echo "❌ .ipa not produced"; exit 1
fi

# --- stage archive for Xcode Organizer --------------------------------
DATE=$(date +%Y-%m-%d)
XC_ARCHIVES=~/Library/Developer/Xcode/Archives/$DATE
mkdir -p "$XC_ARCHIVES"
rm -rf "$XC_ARCHIVES/Writey-iOS.xcarchive"
cp -R build/Writey-iOS.xcarchive "$XC_ARCHIVES/"
echo "▸ Archive staged at $XC_ARCHIVES/Writey-iOS.xcarchive (visible in Xcode Organizer)"

# --- upload to App Store Connect --------------------------------------
echo "▸ Uploading to App Store Connect via TestFlight…"
xcrun altool --upload-app \
  -f "$IPA" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  2>&1 | tail -5

echo ""
echo "✅ Writey-iOS $VERSION ($BUILD) uploaded."
echo "   Processing on Apple's end takes 5–20 min."
echo "   Check status: https://appstoreconnect.apple.com/apps"
echo "   Install on iPad: TestFlight app → Writey → Install"
