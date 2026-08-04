#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="GitAgent.app"
BUILD_ROOT="$ROOT_DIR/.build/release"
APP_PATH="$BUILD_ROOT/Build/Products/Release/$APP_NAME"
INSTALL_PATH="/Applications/$APP_NAME"

cd "$ROOT_DIR"

echo "Building $APP_NAME (Release)..."
xcodebuild \
  -project GitAgent.xcodeproj \
  -scheme GitAgent \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$BUILD_ROOT" \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "Build finished but app not found: $APP_PATH" >&2
  exit 1
fi

echo "Built app:"
echo "  $APP_PATH"

if [[ "${1:-}" == "--install" ]]; then
  echo "Installing to $INSTALL_PATH"
  rm -rf "$INSTALL_PATH"
  cp -R "$APP_PATH" "$INSTALL_PATH"
  echo "Installed:"
  echo "  $INSTALL_PATH"
fi
