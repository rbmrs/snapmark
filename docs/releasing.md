# Releasing Snapmark

Snapmark's public install path is Homebrew Cask, served from this repository —
the app repo doubles as its own Homebrew tap:

```sh
brew tap rbmrs/snapmark https://github.com/rbmrs/snapmark
brew trust rbmrs/snapmark
brew install --cask snapmark
```

The cask lives at `Casks/snapmark.rb`. The two-argument `brew tap` form is needed
because the repo is named `snapmark`, not `homebrew-snapmark`, and `brew trust`
is required on Homebrew 6.0+, which refuses to load third-party taps until they
are explicitly trusted.

`scripts/package-release.sh` regenerates `Casks/snapmark.rb` from the same build
it zips, so the cask's `sha256` always matches the uploaded artifact. The release
workflow commits that regenerated cask back to `main`.

## Requirements

- A Swift toolchain. The universal binary is built by compiling each
  architecture separately and merging them with `lipo`, so plain Command Line
  Tools are sufficient — full Xcode is not required.
- Homebrew, for validating the generated cask.
- GitHub permission to publish releases in `rbmrs/snapmark`. The cask bump is a
  same-repo push using the workflow's default `GITHUB_TOKEN` — no PAT needed.
  (It does require `main` to allow direct pushes from `github-actions[bot]`.)

No Apple Developer Program membership is required. Releases are ad-hoc signed
with Snapmark's stable bundle identifier, so they are not notarized; the cask
strips the quarantine flag on install so the app still launches.

## Release Flow

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in
   `Snapmark/Info.plist`.
2. Verify the app:

   ```sh
   swift build -Xswiftc -warnings-as-errors
   swift run SnapmarkVerification
   ```

3. Package the universal app:

   ```sh
   ./scripts/package-release.sh
   ```

   This creates:

   ```text
   dist/release/Snapmark-<version>.zip
   dist/release/SHA256SUMS.txt
   dist/release/snapmark.rb
   ```

4. Verify the built bundle:

   ```sh
   plutil -lint dist/build/Snapmark.app/Contents/Info.plist
   codesign --verify --deep --strict --verbose=2 dist/build/Snapmark.app
   lipo -info dist/build/Snapmark.app/Contents/MacOS/Snapmark   # arm64 + x86_64
   shasum -a 256 dist/release/Snapmark-<version>.zip
   ```

5. Create and push a version tag:

   ```sh
   git tag v<version>
   git push origin v<version>
   ```

   The release workflow then builds the universal app, publishes the GitHub
   release, and commits the regenerated `Casks/snapmark.rb` to `main`.

6. Manual fallback (only if the workflow is disabled): upload
   `dist/release/Snapmark-<version>.zip` and `dist/release/SHA256SUMS.txt` to the
   release, then copy `dist/release/snapmark.rb` over `Casks/snapmark.rb`, commit,
   and push to `main`.

7. Test the published cask:

   ```sh
   brew tap rbmrs/snapmark https://github.com/rbmrs/snapmark
   brew trust rbmrs/snapmark
   brew style Casks/snapmark.rb
   brew install --cask snapmark
   open -a Snapmark
   ```

## Manual Acceptance

- First launch works from the Brew-installed app.
- First capture asks for Screen Recording permission.
- The global shortcut works without Accessibility permission.
- Capture, annotate, and Return-to-copy work.
- Upgrading between cask versions preserves Screen Recording permission where
  macOS allows it.
