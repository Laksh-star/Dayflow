#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Dayflow/Dayflow.xcodeproj"
DERIVED_DATA_PATH="$ROOT_DIR/DerivedDataDev"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Debug/Dayflow Dev.app"
INSTALL_APP="/Applications/Dayflow Dev.app"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

echo "Building Dayflow Dev..."
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme Dayflow \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  build \
  -quiet

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Build finished, but app was not found at: $BUILT_APP" >&2
  exit 1
fi

echo "Installing to /Applications..."
ditto "$BUILT_APP" "$INSTALL_APP"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INSTALL_APP/Contents/Info.plist")"
APP_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$INSTALL_APP/Contents/Info.plist")"

echo "Installed $APP_NAME"
echo "Bundle ID: $BUNDLE_ID"
echo "Path: $INSTALL_APP"
