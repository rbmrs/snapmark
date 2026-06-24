cask "snapmark" do
  arch arm: "arm64", intel: "x86_64"

  version "1.0.2"
  sha256 arm:   "ff077cd032172bebedd127fbde7b2553273b57b13c14013dd711eafd4b436fcb",
         intel: "dfac0848007f3c90c2474e036cc5a68b52b5fc9f6a71438931f08fcba2a431e7"

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
