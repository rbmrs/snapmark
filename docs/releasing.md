# Releasing Snapmark

Snapmark's public install path is Homebrew Cask:

```sh
brew install --cask rbmrs/snapmark/snapmark
```

The cask lives in the project-owned tap `rbmrs/homebrew-snapmark`. The main app
repository owns the release artifacts and generates the tap-ready cask. Always
copy the generated `snapmark.rb` from the same packaging run as the uploaded zip
files; its checksums must match those exact artifacts.

## Requirements

- Full Xcode or a Swift toolchain capable of building both `arm64` and `x86_64`.
- Homebrew, for validating the generated cask.
- GitHub permissions to publish releases in `rbmrs/snapmark` and push to
  `rbmrs/homebrew-snapmark`.

No Apple Developer Program membership is required. Releases are ad-hoc signed
with Snapmark's stable bundle identifier, so they are not notarized.

## Release Flow

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Snapmark/Info.plist`.
2. Verify the app:

   ```sh
   swift build -Xswiftc -warnings-as-errors
   swift run SnapmarkVerification
   ```

3. Package both architectures:

   ```sh
   ./scripts/package-release.sh
   ```

   This creates:

   ```text
   dist/release/Snapmark-<version>-arm64.zip
   dist/release/Snapmark-<version>-x86_64.zip
   dist/release/SHA256SUMS.txt
   dist/release/snapmark.rb
   ```

4. Verify the app bundle produced for each architecture:

   ```sh
   plutil -lint dist/build-arm64/Snapmark.app/Contents/Info.plist
   codesign --verify --deep --strict --verbose=2 dist/build-arm64/Snapmark.app
   plutil -lint dist/build-x86_64/Snapmark.app/Contents/Info.plist
   codesign --verify --deep --strict --verbose=2 dist/build-x86_64/Snapmark.app
   shasum -a 256 dist/release/Snapmark-<version>-*.zip
   ```

5. Create and push a version tag:

   ```sh
   git tag v<version>
   git push origin v<version>
   ```

6. Upload the files in `dist/release/` to the matching GitHub release.
   If the release workflow is enabled, the tag push performs this step.

7. Copy `dist/release/snapmark.rb` to
   `rbmrs/homebrew-snapmark/Casks/snapmark.rb`, commit it, and push the tap.

8. Test the published cask:

   ```sh
   brew tap rbmrs/snapmark
   brew audit --cask --strict --tap=rbmrs/snapmark snapmark
   brew install --cask rbmrs/snapmark/snapmark
   open -a Snapmark
   ```

## Manual Acceptance

- First launch works from the Brew-installed app.
- First capture asks for Screen Recording permission.
- The global shortcut works without Accessibility permission.
- Capture, annotate, and Return-to-copy work.
- Upgrading between cask versions preserves Screen Recording permission where
  macOS allows it.
