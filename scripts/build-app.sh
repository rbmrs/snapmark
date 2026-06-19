#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_DIR="$OUTPUT_DIR/Printy.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

echo "Building Printy ($CONFIGURATION)…"
swift build \
  --configuration "$CONFIGURATION" \
  --product Printy \
  -Xswiftc -warnings-as-errors

BIN_DIR="$(swift build --configuration "$CONFIGURATION" --show-bin-path)"
EXECUTABLE="$BIN_DIR/Printy"

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Build succeeded but the Printy executable was not found at:"
  echo "$EXECUTABLE"
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE" "$MACOS_DIR/Printy"
cp "$ROOT_DIR/Printy/Info.plist" "$CONTENTS_DIR/Info.plist"

chmod 755 "$MACOS_DIR/Printy"

echo "Signing Printy.app with a stable local requirement…"
codesign \
  --force \
  --sign - \
  --identifier com.rafaelbm.Printy \
  --requirements '=designated => identifier "com.rafaelbm.Printy"' \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"

echo
echo "Built:"
echo "$APP_DIR"
