#!/bin/bash
#
# One-shot: bump build number, archive Writey for iOS and/or macOS,
# export and upload to App Store Connect for TestFlight, copy archives
# to Xcode Organizer's default location.
#
# Both platforms share one App Store Connect record (bundle ID
# com.writey.Writey, iOS + macOS) and one build number.
#
# Auth: the Apple ID signed into Xcode (Settings ▸ Accounts) for team
# 8B29CDK832. The export step uploads directly (destination: upload in
# scripts/ExportOptions.plist), so no App Store Connect API key is needed.
#
# Usage:
#   ./scripts/ship.sh                  # bumps CURRENT_PROJECT_VERSION, ships iOS + macOS
#   ./scripts/ship.sh ios              # just iPhone/iPad
#   ./scripts/ship.sh macos            # just Mac
#   ./scripts/ship.sh all --no-bump    # ships current build number as-is
#
set -euo pipefail

cd "$(dirname "$0")/.."

PLATFORMS="all"
BUMP=1
for arg in "$@"; do
  case "$arg" in
    ios|macos|all) PLATFORMS="$arg" ;;
    --no-bump)     BUMP=0 ;;
    *) echo "Unknown argument '$arg' (use ios, macos, all, --no-bump)"; exit 1 ;;
  esac
done

# --- pre-flight sanity checks -----------------------------------------
if [ ! -f "Sources/Writey/Core/Sync/SyncConfig.swift" ]; then
  echo "❌ Sources/Writey/Core/Sync/SyncConfig.swift is missing."
  echo "   cp Sources/Writey/Core/Sync/SyncConfig.template.swift Sources/Writey/Core/Sync/SyncConfig.swift"
  exit 1
fi

# --- bump build number (default) --------------------------------------
if [ "$BUMP" = 1 ]; then
  CUR=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
  NEW=$((CUR + 1))
  echo "▸ Bumping CURRENT_PROJECT_VERSION: $CUR → $NEW"
  /usr/bin/sed -i '' "s/CURRENT_PROJECT_VERSION: \"$CUR\"/CURRENT_PROJECT_VERSION: \"$NEW\"/" project.yml
fi

VERSION=$(awk -F'"' '/MARKETING_VERSION:/ {print $2; exit}' project.yml)
BUILD=$(awk -F'"' '/CURRENT_PROJECT_VERSION:/ {print $2; exit}' project.yml)
echo "▸ Shipping Writey $VERSION ($BUILD) → $PLATFORMS"

# --- regenerate --------------------------------------------------------
echo "▸ xcodegen generate"
xcodegen generate | tail -1

DATE=$(date +%Y-%m-%d)
XC_ARCHIVES=~/Library/Developer/Xcode/Archives/$DATE

# ship <label> <scheme> <destination>
ship() {
  local label="$1" scheme="$2" dest="$3"
  local archive="build/Writey-$label.xcarchive"

  echo "▸ [$label] archive (this takes ~1 min)"
  rm -rf "$archive" "build/Writey-$label-export"
  xcodebuild archive \
    -project Writey.xcodeproj \
    -scheme "$scheme" \
    -configuration Release \
    -destination "$dest" \
    -archivePath "$archive" \
    -allowProvisioningUpdates \
    | tail -3

  if [ ! -d "$archive" ]; then
    echo "❌ [$label] archive not produced — check xcodebuild output above"; exit 1
  fi

  echo "▸ [$label] export and upload to App Store Connect for TestFlight…"
  xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportPath "build/Writey-$label-export" \
    -exportOptionsPlist scripts/ExportOptions.plist \
    -allowProvisioningUpdates \
    | tail -3

  # Stage archive for Xcode Organizer.
  mkdir -p "$XC_ARCHIVES"
  rm -rf "$XC_ARCHIVES/Writey-$label.xcarchive"
  cp -R "$archive" "$XC_ARCHIVES/"
  echo "▸ [$label] archive staged at $XC_ARCHIVES/Writey-$label.xcarchive (visible in Xcode Organizer)"
  echo "✓ [$label] Writey $VERSION ($BUILD) uploaded."
}

case "$PLATFORMS" in
  ios)   ship iOS Writey-iOS 'generic/platform=iOS' ;;
  macos) ship macOS Writey 'generic/platform=macOS' ;;
  all)   ship iOS Writey-iOS 'generic/platform=iOS'
         ship macOS Writey 'generic/platform=macOS' ;;
esac

echo ""
echo "✅ Writey $VERSION ($BUILD) uploaded."
echo "   Processing on Apple's end takes 5–20 min."
echo "   Check status: https://appstoreconnect.apple.com/apps"
echo "   Install: TestFlight app (iPhone, iPad or Mac) → Writey → Install"
