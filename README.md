# Printy

Printy is a native macOS menu-bar screenshot tool. Press a configurable global shortcut, click two corners to select a region, add rectangle or arrow annotations, and press Return to copy the result as a PNG.

## Requirements

- macOS 15.2 or newer
- Apple Command Line Tools

Install the tools once if needed:

```sh
xcode-select --install
```

Full Xcode is optional.

## Build and run without Xcode

From this repository:

```sh
./scripts/run-app.sh
```

This compiles a release build, creates `dist/Printy.app`, applies a stable local designated requirement, verifies the bundle, and launches it. The stable requirement prevents macOS from identifying every rebuild solely by its changing binary hash.

To install it under your user Applications folder:

```sh
./scripts/install-app.sh
```

This installs and launches `~/Applications/Printy.app`. On the first capture, allow Printy under **System Settings → Privacy & Security → Screen & System Audio Recording**.

No Accessibility permission is required.

An Apple Developer certificate is only necessary later for distributing Printy to other Macs.

## Usage

- Default global shortcut: `⌥⇧4`
- First and second clicks: choose the screenshot corners
- Rectangle or Arrow: click two endpoints
- Select: click an annotation, then drag it or one of its handles
- `V`, `R`, `A`: select, rectangle, and arrow tools
- `⌘Z`: undo
- Delete: remove the selected annotation
- Return: copy the annotated crop and close
- Escape: cancel the current annotation, or cancel the capture

The menu-bar Settings window can change the global shortcut and optionally enable Launch at Login.

## Verification

With Command Line Tools:

```sh
swift build -Xswiftc -warnings-as-errors
swift run PrintyVerification
```

Full Xcode can additionally run the XCTest suite:

```sh
xcodebuild -project Printy.xcodeproj -scheme Printy test
```
