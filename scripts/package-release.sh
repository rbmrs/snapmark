#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Snapmark/Info.plist")}"
ARCHS="${ARCHS:-arm64 x86_64}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RELEASE_DIR="${RELEASE_DIR:-$OUTPUT_DIR/release}"

typeset -A SHAS

rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

for ARCH in ${(s: :)ARCHS}; do
  BUILD_DIR="$OUTPUT_DIR/build-$ARCH"
  ZIP_NAME="Snapmark-$VERSION-$ARCH.zip"
  ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"

  rm -rf "$BUILD_DIR"
  ARCH="$ARCH" OUTPUT_DIR="$BUILD_DIR" "$ROOT_DIR/scripts/build-app.sh"

  find "$BUILD_DIR/Snapmark.app" -exec touch -t 202001010000 {} +

  echo "Packaging $ZIP_NAME…"
  rm -f "$ZIP_PATH"
  (
    cd "$BUILD_DIR"
    zip -qry -X "$ZIP_PATH" "Snapmark.app"
  )

  SHAS[$ARCH]="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
done

if [[ -z "${SHAS[arm64]:-}" || -z "${SHAS[x86_64]:-}" ]]; then
  echo "Release packaging requires both arm64 and x86_64 artifacts."
  echo "Set ARCHS='arm64 x86_64' or leave ARCHS unset."
  exit 1
fi

{
  for ARCH in ${(s: :)ARCHS}; do
    echo "${SHAS[$ARCH]}  Snapmark-$VERSION-$ARCH.zip"
  done
} > "$RELEASE_DIR/SHA256SUMS.txt"

CASK_PATH="$RELEASE_DIR/snapmark.rb"
cat > "$CASK_PATH" <<EOF
cask "snapmark" do
  arch arm: "arm64", intel: "x86_64"

  version "$VERSION"
  sha256 arm:   "${SHAS[arm64]}",
         intel: "${SHAS[x86_64]}"

  url "https://github.com/rbmrs/snapmark/releases/download/v#{version}/Snapmark-#{version}-#{arch}.zip"
  name "Snapmark"
  desc "Screenshot annotation tool"
  homepage "https://github.com/rbmrs/snapmark"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sequoia

  app "Snapmark.app"

  zap trash: "~/Library/Preferences/com.rafaelbm.Snapmark.plist"

  caveats <<~EOS
    Snapmark is unsigned and distributed from the rbmrs/snapmark tap.
    macOS will still ask for Screen Recording permission on first capture.
  EOS
end
EOF

echo
echo "Release artifacts:"
ls -1 "$RELEASE_DIR"
echo
echo "SHA-256:"
cat "$RELEASE_DIR/SHA256SUMS.txt"
echo
echo "Tap cask generated at:"
echo "$CASK_PATH"
