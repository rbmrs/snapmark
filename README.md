# Printy

Minimal macOS screenshot annotation from the menu bar.

Press `⌥⇧4`, click two corners, add rectangles or arrows, then press Return to copy the result.

## Install

Requires macOS 15.2+ and Apple Command Line Tools:

```sh
xcode-select --install
./scripts/install-app.sh
```

Allow Screen Recording when macOS prompts. Full Xcode and Accessibility permission are not required.

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
swift run PrintyVerification
```
