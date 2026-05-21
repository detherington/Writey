#!/bin/bash
#
# Build a release .app, sign it with your Developer ID Application cert,
# wrap it in a DMG, sign that, notarize via Apple's notary service, and
# staple the notarization ticket so the DMG is trusted offline.
#
# The result: a DMG you can drop onto any Mac (yours, friends', whatever)
# and double-click to install with zero Gatekeeper warnings.
#
# ONE-TIME SETUP (do once, ever, on this machine):
#
#   1. Go to https://account.apple.com/account/manage
#        → Sign-In and Security → App-Specific Passwords
#        → Generate password (label it "Writey Notary")
#      Save it — Apple won't show it to you again.
#
#   2. Store it in your Keychain so this script can use it without
#      ever seeing the plaintext password:
#
#      xcrun notarytool store-credentials "Picsy" \
#          --apple-id darrell@theangle.com \
#          --team-id 8B29CDK832 \
#          --password '<paste-app-specific-password-here>'
#
#      That writes a Keychain item; the script references it by the
#      profile name "Picsy" forever after.
#
# USAGE:
#   ./scripts/build-dmg.sh              # builds Writey-<version-from-project.yml>.dmg
#   ./scripts/build-dmg.sh 0.2.0        # overrides the version
#
set -euo pipefail

cd "$(dirname "$0")/.."

# ────────────────────────────────────────────────────────────────────────
# Preflight
# ────────────────────────────────────────────────────────────────────────

if [ ! -f "Sources/Writey/Core/Sync/SyncConfig.swift" ]; then
  echo "❌ Sources/Writey/Core/Sync/SyncConfig.swift is missing."
  echo "   Run:  cp Sources/Writey/Core/Sync/SyncConfig.template.swift \\"
  echo "         Sources/Writey/Core/Sync/SyncConfig.swift"
  echo "   Then paste in your OAuth client ID + redirect scheme."
  exit 1
fi

IDENTITY="Developer ID Application: Darrell Etherington (8B29CDK832)"
NOTARY_PROFILE="Picsy"

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
  echo "❌ Couldn't find '$IDENTITY' in your Keychain."
  echo "   The cert may have expired or been removed. Re-download it from"
  echo "   https://developer.apple.com/account/resources/certificates."
  exit 1
fi

if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "❌ Keychain profile '$NOTARY_PROFILE' isn't set up yet."
  echo "   See the ONE-TIME SETUP comment at the top of this script."
  exit 1
fi

VERSION="${1:-$(awk -F'"' '/MARKETING_VERSION:/ {print $2}' project.yml)}"
DMG="Writey-${VERSION}.dmg"
BUILD_DIR="build"

# ────────────────────────────────────────────────────────────────────────
# Build
# ────────────────────────────────────────────────────────────────────────

echo "▸ xcodegen generate"
xcodegen generate >/dev/null

echo "▸ xcodebuild (Release, Developer ID signed, hardened runtime)"
xcodebuild \
  -project Writey.xcodeproj \
  -scheme Writey \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  DEVELOPMENT_TEAM=8B29CDK832 \
  PROVISIONING_PROFILE_SPECIFIER="" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build \
  | tail -20

APP_PATH=$(find "$BUILD_DIR/Build/Products/Release" -maxdepth 2 -name "Writey.app" -type d | head -1)
if [ -z "$APP_PATH" ]; then
  echo "❌ Couldn't find built Writey.app"; exit 1
fi
echo "▸ Built: $APP_PATH"

# Re-sign the .app with our entitlements file explicitly. xcodebuild's
# `build` action (vs `archive`) leaves `com.apple.security.get-task-allow`
# = true even in Release config, which Apple's notary service rejects.
# Our entitlements file doesn't include that key, so this overrides
# Xcode's auto-injected signature with the right one.
ENTITLEMENTS_FILE="Sources/Writey/macOS/Writey.entitlements"
echo "▸ Re-signing .app with explicit Release entitlements (strips get-task-allow)"
codesign --force --sign "$IDENTITY" \
  --options=runtime \
  --timestamp \
  --entitlements "$ENTITLEMENTS_FILE" \
  "$APP_PATH"

echo "▸ Verifying .app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | tail -5
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "(Authority|TeamIdentifier|flags)" | head -5
echo "▸ Confirming get-task-allow is absent"
codesign -d --entitlements - "$APP_PATH" 2>&1 | grep -q "get-task-allow" \
  && { echo "❌ get-task-allow still present, notarization will fail"; exit 1; } \
  || echo "  ✓ get-task-allow not present"

# ────────────────────────────────────────────────────────────────────────
# Package as DMG
# ────────────────────────────────────────────────────────────────────────

STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
echo "▸ Creating DMG"
hdiutil create \
  -srcfolder "$STAGING" \
  -volname "Writey" \
  -fs APFS \
  -format UDZO \
  -ov "$DMG" \
  > /dev/null
rm -rf "$STAGING"

echo "▸ Signing DMG (Developer ID + timestamp + hardened runtime)"
codesign --sign "$IDENTITY" --timestamp --options=runtime "$DMG"

# ────────────────────────────────────────────────────────────────────────
# Notarize
# ────────────────────────────────────────────────────────────────────────

echo "▸ Submitting DMG to Apple's notary service…"
echo "   (takes 1–5 min usually; Apple scans for malware and signs a ticket)"
xcrun notarytool submit "$DMG" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait

echo "▸ Stapling notarization ticket to DMG"
xcrun stapler staple "$DMG"

# ────────────────────────────────────────────────────────────────────────
# Verify
# ────────────────────────────────────────────────────────────────────────

echo "▸ Gatekeeper assessment (should say 'accepted')"
spctl -a -t open --context context:primary-signature -v "$DMG" 2>&1 | head -3

SIZE=$(du -h "$DMG" | cut -f1)
echo ""
echo "✅ $DMG ($SIZE) — signed, notarized, stapled."
echo "   Copy this file to any Mac, double-click — opens with no warnings."
