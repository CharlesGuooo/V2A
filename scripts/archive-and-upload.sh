#!/bin/bash
# Archives V2A (Release) and uploads to App Store Connect (TestFlight),
# fully headless via an App Store Connect API key + manual signing.
#
# Why manual signing: xcodebuild cloud-signing fails in this environment
# ("Cloud signing permission error"). Instead we use a distribution cert whose
# private key lives in the login keychain, plus an App Store profile created via
# the API (scripts/make_appstore_profile.py). See that script if the profile
# needs recreating.
#
# Prereqs (already set up in this repo/machine):
#   - API key .p8 at ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8 (App Manager role)
#   - "Apple Distribution" identity in the login keychain
#   - App Store profile named "$PROFILE_NAME" installed
#
# Optional env:
#   KEYCHAIN_PWD  login keychain password (to unlock + allow codesign non-interactively)
#
# Usage: ./scripts/archive-and-upload.sh

set -euo pipefail
cd "$(dirname "$0")/.."

# App Store Connect API key — set these in your environment, never commit them.
KEY_ID="${ASC_KEY_ID:?set ASC_KEY_ID}"
ISSUER="${ASC_ISSUER_ID:?set ASC_ISSUER_ID}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"
TEAM_ID="${ASC_TEAM_ID:-SRYLV3Q454}"
PROFILE_NAME="V2A App Store (api)"
ARCHIVE="build/V2A.xcarchive"
EXPORT_DIR="build/V2A-ipa"
OPTS="build/ExportOptions.plist"

echo "==> 1/5  Regenerate project"
xcodegen generate --quiet

echo "==> 2/5  Archive (Release)"
rm -rf "$ARCHIVE"
xcodebuild -project V2A.xcodeproj -scheme V2A -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates archive

echo "==> 3/5  Unlock keychain for codesign (if KEYCHAIN_PWD set)"
if [ -n "${KEYCHAIN_PWD:-}" ]; then
  LOGIN="$HOME/Library/Keychains/login.keychain-db"
  security unlock-keychain -p "$KEYCHAIN_PWD" "$LOGIN"
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PWD" "$LOGIN" >/dev/null 2>&1 || true
fi

echo "==> 4/5  Write ExportOptions (manual signing)"
mkdir -p build
cat > "$OPTS" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>manual</string>
  <key>signingCertificate</key><string>Apple Distribution</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>com.charlesgxy.v2a</key><string>${PROFILE_NAME}</string>
  </dict>
</dict>
</plist>
EOF

echo "==> 5/5  Export + upload"
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTS" \
  -exportPath "$EXPORT_DIR" \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER"

echo ""
echo "✓ Uploaded. App Store Connect → V2A → TestFlight (build shows up in ~10-30 min)."
