# Snapmark

Minimal macOS screenshot annotation from the menu bar.

Press `⌥⇧4`, click two corners, add rectangles or arrows, then press Return to copy the result.

## Install

Requires macOS 15.2+ and Homebrew:

```sh
brew tap rbmrs/snapmark
brew install --cask snapmark
open -a Snapmark
```

Homebrew installs a prebuilt app. Xcode and Apple Command Line Tools are not required.

Allow Screen Recording when macOS prompts on first capture. Snapmark does not require Accessibility permission.

Snapmark is unsigned and not notarized, so macOS may still ask you to approve opening it.

## Usage

- `⌥⇧4`: start capture
- Two clicks: select the crop or draw an annotation
- `V`, `R`, `A`: select, rectangle, arrow
- `⌘Z`: undo
- Delete: remove selection
- Return: copy and close
- Escape: cancel

The global shortcut is configurable from the menu-bar settings.

## Development

```sh
swift build -Xswiftc -warnings-as-errors
swift run SnapmarkVerification
```

Release packaging is documented in [docs/releasing.md](docs/releasing.md).
