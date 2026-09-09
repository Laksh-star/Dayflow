#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Dayflow/Dayflow.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedDataDev"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Debug/Dayward.app"
INSTALL_APP="/Applications/Dayward.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

if [[ "${DAYFLOW_ALLOW_ADHOC_SIGNING:-0}" != "1" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Apple Development|Mac Developer|Developer ID Application/ { print $2; exit }')"

  if [[ -z "${SIGNING_IDENTITY:-}" ]]; then
    cat >&2 <<'EOF'
No valid code-signing identity was found.

Dayward needs a stable signing identity for macOS Screen & System Audio
Recording permission to survive rebuilds. Create an Apple Development certificate
in Xcode first, then rerun this script.

Temporary ad-hoc builds are still possible with:
  DAYFLOW_ALLOW_ADHOC_SIGNING=1 ./scripts/install-dev-app.sh

EOF
    exit 1
  fi
else
  SIGNING_IDENTITY="-"
fi

echo "Building Dayward..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme Dayflow \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM= \
  PROVISIONING_PROFILE_SPECIFIER= \
  build \
  -quiet

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build finished, but app was not found at: $BUILT_APP" >&2
  exit 1
fi

echo "Installing to /Applications..."
ditto "$BUILT_APP" "$INSTALL_APP"

echo "Cleaning LaunchServices registrations for build-output copies..."
find "$ROOT_DIR" -path '*/Build/Products/*/Dayward.app' -type d -prune -print0 |
  while IFS= read -r -d '' app_path; do
    if [[ "$app_path" != "$INSTALL_APP" ]]; then
      "$LSREGISTER" -u "$app_path" 2>/dev/null || true
    fi
  done

"$LSREGISTER" -f -R -trusted "$INSTALL_APP" 2>/dev/null || true

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_APP/Contents/Info.plist")"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INSTALL_APP/Contents/Info.plist")"

echo "Installed $APP_NAME"
echo "Bundle ID: $BUNDLE_ID"
echo "Path: $INSTALL_APP"
