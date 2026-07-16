#!/bin/bash
# Build V2A.app for iOS device, install onto the connected iPhone, and launch.
# Usage: ./scripts/build-and-install.sh
set -euo pipefail

cd "$(dirname "$0")/.."

# Your connected iPhone's UDID: xcrun devicectl list devices
DEVICE_ID="${V2A_DEVICE_ID:?set V2A_DEVICE_ID to your iPhone UDID (xcrun devicectl list devices)}"
BUNDLE_ID="com.charlesgxy.v2a"
SCHEME="V2A"
DERIVED="build"

echo "==> 1/4  Regenerating .xcodeproj from project.yml"
xcodegen generate --quiet

echo "==> 2/4  xcodebuild for iphoneos"
xcodebuild \
  -project V2A.xcodeproj \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED" \
  -allowProvisioningUpdates \
  build | tail -40

APP_PATH="$DERIVED/Build/Products/Debug-iphoneos/V2A.app"
if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: $APP_PATH not found after build"
  exit 1
fi

echo "==> 3/4  Installing $APP_PATH to device $DEVICE_ID"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo "==> 4/4  Launching $BUNDLE_ID"
xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID"

echo "Done. Check your iPhone."
