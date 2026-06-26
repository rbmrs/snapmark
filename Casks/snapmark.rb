# Homebrew Cask for Snapmark — a menu-bar screenshot annotation app.
#
# Install:
#   brew tap rbmrs/snapmark https://github.com/rbmrs/snapmark
#   brew trust rbmrs/snapmark   # required on Homebrew 6.0+
#   brew install --cask snapmark
#
# The 2-arg `brew tap` form is required because the repo is named `snapmark`,
# not `homebrew-snapmark`. See https://docs.brew.sh/Taps.

cask "snapmark" do
  version "1.0.6"
  sha256 "49913f621e7b9175444818daab81cbc4e1ee437eb81bf399e62a6dd7fd136f28"

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
