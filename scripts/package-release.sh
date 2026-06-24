#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw -o - "$ROOT_DIR/Snapmark/Info.plist")}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/dist}"
RELEASE_DIR="${RELEASE_DIR:-$OUTPUT_DIR/release}"
BUILD_DIR="${BUILD_DIR:-$OUTPUT_DIR/build}"

rm -rf "$RELEASE_DIR" "$BUILD_DIR"
mkdir -p "$RELEASE_DIR"

# Build one universal (arm64 + x86_64) app bundle.
OUTPUT_DIR="$BUILD_DIR" "$ROOT_DIR/scripts/build-app.sh"

# Normalize timestamps so the archive is reproducible across runs.
find "$BUILD_DIR/Snapmark.app" -exec touch -t 202001010000 {} +

ZIP_NAME="Snapmark-$VERSION.zip"
ZIP_PATH="$RELEASE_DIR/$ZIP_NAME"
echo "Packaging $ZIP_NAME…"
(
  cd "$BUILD_DIR"
  zip -qry -X "$ZIP_PATH" "Snapmark.app"
)

SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "$SHA  $ZIP_NAME" > "$RELEASE_DIR/SHA256SUMS.txt"

# Generate the tap-ready cask. The main repo doubles as the Homebrew tap, so the
# release workflow copies this file over Casks/snapmark.rb on main.
CASK_PATH="$RELEASE_DIR/snapmark.rb"
cat > "$CASK_PATH" <<EOF
# Homebrew Cask for Snapmark — a menu-bar screenshot annotation app.
#
# Install:
#   brew tap rbmrs/snapmark https://github.com/rbmrs/snapmark
#   brew trust rbmrs/snapmark   # required on Homebrew 6.0+
#   brew install --cask snapmark
#
# The 2-arg \`brew tap\` form is required because the repo is named \`snapmark\`,
# not \`homebrew-snapmark\`. See https://docs.brew.sh/Taps.

cask "snapmark" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/rbmrs/snapmark/releases/download/v#{version}/Snapmark-#{version}.zip"
  name "Snapmark"
  desc "Screenshot annotation tool"
  homepage "https://github.com/rbmrs/snapmark"

  livecheck do
    url :url
    strategy :github_latest
  end

  # The app's Info.plist sets a 15.2 minimum; :sequoia (15.0) is the closest
  # symbol Homebrew exposes, so 15.0–15.1 users are gated by the app itself.
  depends_on macos: :sequoia

  app "Snapmark.app"

  # Snapmark is ad-hoc signed (no Apple Developer ID). Stripping the quarantine
  # xattr stops Gatekeeper from blocking the unsigned app on first launch. Safe
  # because the user explicitly opted into this tap.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Snapmark.app"],
                   sudo: false
  end

  zap trash: "~/Library/Preferences/com.rafaelbm.Snapmark.plist"

  caveats <<~CAVEATS
    Snapmark asks for Screen Recording permission on first capture.
    It does not require Accessibility permission.
  CAVEATS
end
EOF

echo
echo "Release artifacts:"
ls -1 "$RELEASE_DIR"
echo
echo "SHA-256:"
cat "$RELEASE_DIR/SHA256SUMS.txt"
echo
echo "Cask generated at:"
echo "$CASK_PATH"
