#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
ARCHS="${ARCHS:-arm64 x86_64}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
APP_DIR="${APP_DIR:-$OUTPUT_DIR/Snapmark.app}"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

echo "Building Snapmark ($CONFIGURATION, archs: $ARCHS)…"

# Build each architecture as a separate single-arch slice. This uses SwiftPM's
# native build system, which works under plain Command Line Tools — unlike a
# multi-arch (`--arch a --arch b`) build, which requires full Xcode's xcbuild.
# The slices are merged into a universal binary with lipo below.
SLICES=()
for ARCH in ${(s: :)ARCHS}; do
  echo "  • $ARCH"
  swift build \
    --configuration "$CONFIGURATION" \
    --product Snapmark \
    --arch "$ARCH" \
    -Xswiftc -warnings-as-errors
  SLICE="$(swift build --configuration "$CONFIGURATION" --arch "$ARCH" --show-bin-path)/Snapmark"
  if [[ ! -x "$SLICE" ]]; then
    echo "Build succeeded but the $ARCH executable was not found at:"
    echo "$SLICE"
    exit 1
  fi
  SLICES+=("$SLICE")
done

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Merging slices into a universal binary…"
lipo -create "${SLICES[@]}" -output "$MACOS_DIR/Snapmark"

cp "$ROOT_DIR/Snapmark/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Snapmark/Resources/Snapmark.icns" "$RESOURCES_DIR/Snapmark.icns"

chmod 755 "$MACOS_DIR/Snapmark"

echo "Signing Snapmark.app with a stable local requirement…"
codesign \
  --force \
  --sign - \
  --identifier com.rafaelbm.Snapmark \
  --requirements '=designated => identifier "com.rafaelbm.Snapmark"' \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
plutil -lint "$CONTENTS_DIR/Info.plist"

echo
echo "Built:"
echo "$APP_DIR"
lipo -info "$MACOS_DIR/Snapmark"
