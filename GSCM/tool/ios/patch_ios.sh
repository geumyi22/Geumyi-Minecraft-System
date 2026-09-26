#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLIST="$ROOT/ios/Runner/Info.plist"
APP_DELEGATE="$ROOT/ios/Runner/AppDelegate.swift"
TEMPLATE="$ROOT/tool/ios/AppDelegate.swift"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[GSCM] iOS project preparation must run on macOS."
  exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo "[GSCM] Flutter is not installed or not on PATH."
  exit 1
fi
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "[GSCM] Xcode command line tools are not available."
  exit 1
fi

if [[ ! -d "$ROOT/ios/Runner.xcodeproj" ]]; then
  echo "[GSCM] Creating Flutter iOS Runner from the installed Flutter template..."
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  flutter create --platforms=ios --org com.geumyi --project-name gscm "$TMP/gscm_ios"
  rm -rf "$ROOT/ios"
  cp -R "$TMP/gscm_ios/ios" "$ROOT/ios"
fi

cp "$TEMPLATE" "$APP_DELEGATE"

PLISTBUDDY=/usr/libexec/PlistBuddy
plist_set_string() {
  local key="$1" value="$2"
  "$PLISTBUDDY" -c "Delete :$key" "$PLIST" >/dev/null 2>&1 || true
  "$PLISTBUDDY" -c "Add :$key string $value" "$PLIST"
}

plist_set_string "CFBundleDisplayName" "GSCM"
plist_set_string "NSCameraUsageDescription" "GSCM uses the camera only to scan a GSC pairing QR code."
plist_set_string "NSLocalNetworkUsageDescription" "GSCM connects to your Geumyi Server Center on the local network or private VPN."

"$PLISTBUDDY" -c "Add :NSAppTransportSecurity dict" "$PLIST" >/dev/null 2>&1 || true
"$PLISTBUDDY" -c "Delete :NSAppTransportSecurity:NSAllowsLocalNetworking" "$PLIST" >/dev/null 2>&1 || true
"$PLISTBUDDY" -c "Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true" "$PLIST"

# Keep the bundle identifier stable across Android/iOS pairing records and future updates.
PBX="$ROOT/ios/Runner.xcodeproj/project.pbxproj"
if [[ -f "$PBX" ]]; then
  perl -0pi -e 's/PRODUCT_BUNDLE_IDENTIFIER = [^;]+;/PRODUCT_BUNDLE_IDENTIFIER = com.geumyi.gscm;/g' "$PBX"
fi

echo "[GSCM] iOS Runner prepared."
echo "[GSCM] Bundle ID: com.geumyi.gscm"
echo "[GSCM] Secure token storage: Apple Keychain (ThisDeviceOnly)"
