# Running Snapmark on ChromeOS (Crostini)

Study performed 2026-08-02 on the target machine. Everything below was probed
directly on this system, not inferred from documentation.

## Environment

| | |
|---|---|
| Container | Debian GNU/Linux 13 (trixie), x86_64, 2 cores, 2.7 GiB RAM, 6.8 GiB free |
| Session | Wayland (`XDG_SESSION_TYPE=wayland`, `WAYLAND_DISPLAY=wayland-0`) |
| Bridge | `sommelier` (Wayland proxy) + rootless `Xwayland`, `cros-garcon.service` |
| Swift | **Available** — Debian trixie ships `swiftlang 6.0.3-2` in `main` |

Note: `sommelier-x@0` / `sommelier-x@1` are stuck in `activating start`, so X11
is currently dead — `DISPLAY=:0` is set but `xrandr` reports `Can't open display
:0`. Wayland is healthy.

## Verdict

**Snapmark's two core premises — capture the whole screen, and trigger it from a
global hotkey — are both impossible inside Crostini.** Not "hard"; there is no
API surface at any layer. A straight port cannot work.

### Screen capture: blocked at four independent layers

1. **No Wayland capture protocol.** Extracted the full interface list from
   `sommelier.elf` (132 symbols). It proxies `wl_compositor`, `wl_shm`,
   `wl_seat`, `wl_output`, `xdg_wm_base`, `zaura_shell`, `zwp_linux_dmabuf_v1`,
   `zxdg_output_manager_v1`, and the ChromeOS `zcr_*` stylus/gamepad/text-input
   extensions. It proxies **no** `wlr_screencopy`, `ext_image_copy_capture`, or
   any other protocol that lets a client read compositor output. Grepping the
   binary for `screencopy`, `screenshot`, and `capture` returns nothing.

2. **No desktop portal.** `org.freedesktop.impl.portal.desktop.cros` is
   registered on the session bus, but introspecting its entire object tree
   (5 paths) yields **zero interfaces** — it's a stub. The frontend
   `org.freedesktop.portal.Desktop` is activatable but hangs and times out. So no
   `org.freedesktop.portal.Screenshot` and no `ScreenCast`.

3. **No direct framebuffer.** Neither `/dev/dri` nor `/dev/fb0` exists in the
   container. No GPU readback path.

4. **VM isolation.** Crostini runs in the `termina` VM. Even with a capture
   protocol, the guest has no route to the host compositor's buffers.

Under rootless Xwayland the X root window would also not contain ChromeOS host
content — each X client is its own Wayland surface — so `xwd -root` / `import`
would not have worked either, even with X11 up.

### Global hotkey: blocked

- **No `/dev/input`** in the container, so no evdev capture.
- Wayland has no global-hotkey protocol by design, and sommelier exposes no
  `keyboard_shortcuts_inhibit`.
- ChromeOS owns the keyboard. Sommelier's `--accelerators` flag forwards ChromeOS
  accelerators *into* the guest; it does not let a guest app claim a system-wide
  chord.

A Crostini app *can* get a launcher/shelf icon via `garcon` (.desktop files in
`~/.local/share/applications`), so launching is fine — just not by hotkey.

### Platform frameworks

Independently of the above, roughly half the codebase is macOS-only: AppKit,
SwiftUI, ScreenCaptureKit, Carbon HIToolbox, and ServiceManagement have no Linux
equivalents. That covers all of `Snapmark/` (~1,500 lines) plus the AppKit use in
`ImageExporter` and `HistoryManager`.

**What does survive:** `Geometry.swift`, `Annotation.swift`, and
`CaptureSession.swift` — ~350 lines of pure logic, plus their tests. They need
only a `#if canImport(CoreGraphics)` / `import Foundation` shim, since
swift-corelibs-foundation vends `CGRect`, `CGPoint`, and `CGFloat` on Linux.

## Options

### A — PWA / web app  *(recommended for capability)*

The browser is the one thing on ChromeOS that **can** do what the VM cannot:

- `navigator.mediaDevices.getDisplayMedia()` captures screen, window, or tab —
  from the browser, outside the VM sandbox.
- `ClipboardItem` writes a PNG straight to the system clipboard.
- Canvas handles the annotation rendering; the geometry/hit-testing model ports
  near-directly from `SnapmarkCore`.
- Installs to the ChromeOS shelf as a PWA.

Cost: a rewrite in TypeScript. Still no global hotkey — you'd launch from the
shelf, or use ChromeOS's own `Ctrl+Shift+Show Windows` to capture and then paste
into the app.

### B — Linux annotate-only editor  *(recommended for code reuse)*

Drop capture; keep everything else. ChromeOS's built-in screenshot tool writes to
Downloads, which can be shared into Crostini; Snapmark-Linux opens the file,
annotates it, and copies the result via `wl-clipboard` (clipboard crosses the VM
boundary — sommelier proxies `wl_data_device`).

This preserves the Swift core and the annotation model, and drops only the step
ChromeOS already does well. Cost: ~1,500 lines of new GTK4/SDL UI, plus
Linux-native replacements for `ImageExporter` (image encode + clipboard) and
`HistoryManager` (AppKit thumbnailing).

Prerequisite: folder sharing isn't currently set up — `/mnt/chromeos` holds only
`fonts` and a `shared` symlink, no `MyFiles`. Enable "Share with Linux" on a
folder from the ChromeOS Files app.

### C — No port

Keep Snapmark on macOS; use ChromeOS's native screenshot tool plus a web
annotator here. Zero engineering cost.

## Recommendation

If the goal is *"Snapmark's workflow, on this machine"* → **A**. It's the only
option that restores screen capture, and ChromeOS is a browser OS — a PWA is a
first-class citizen on the shelf.

If the goal is *"this codebase, running here"* → **B**, with the honest caveat
that it becomes a different product: an annotation editor, not a capture tool.

The one thing not worth attempting is a faithful port. The blockers are
architectural, not gaps to be worked around.

---

## Decision, 2026-08-02: not pursuing a port

Snapmark stays macOS-only (**option C**). This document is retained as the
record of why; it is not a backlog of open work.

A follow-up review re-tested the environment and re-measured the codebase, and
found several claims above to be wrong or overstated. Corrections below — read
them before trusting anything earlier in this file.

### Corrections to this document

- **"Swift: Available" is the worst claim here, and it kills option B
  outright.** `swiftlang` is in trixie main but **not installed**
  (`apt-cache policy swiftlang` → `Installed: (none)`), is a 444 MB download /
  2.1 GiB installed against 6.8 GiB free, and — decisively — `Package.swift`
  declares `swift-tools-version: 6.1` while Debian ships **6.0.3**. SwiftPM
  refuses manifests newer than the toolchain, so option B never reaches a
  compile error; the manifest won't parse.
- **`ImageExporter` was badly understated.** It isn't "AppKit dependencies" —
  it's **CoreGraphics, which doesn't exist on Linux at all** (only the CG
  *value* types come from swift-corelibs-foundation). `ImageExporter.render`
  and `ImageExporter.draw` are built on
  `CGContext`/`CGImage`/`CGColorSpace`/`CGImageAlphaInfo`. That is a Cairo
  rewrite, not a shim. The only genuinely AppKit line in `render` is
  `NSColor.systemRed.cgColor`.
- **`HistoryManager` was overstated as AppKit-bound** — 122 of its ~150 lines
  are pure Foundation file I/O; only `generateThumbnail` touches AppKit.
- **The "132 symbols" evidence is mislabeled.** Those are libwayland C API
  function symbols, not a protocol interface list. The conclusion holds, but the
  evidence is weaker than presented. Two cleaner proofs:
  `/usr/share/xdg-desktop-portal/portals/gtk.portal` — the only backend
  installed — lists neither Screenshot nor ScreenCast in its `Interfaces=`, and
  `wpctl status` shows PipeWire running with zero Video sources. Its
  `UseIn=gnome` explains the frontend hang. The portal tree is 4 paths, not 5.
- **`wl-clipboard` is not installed** (`Installed: (none)`), so option B's
  clipboard mechanism was never verified. It is plausible — sommelier does proxy
  `wl_data_device_manager`/`wl_data_device`/`wl_data_source` — but it was stated
  as established fact.
- **The folder-sharing "prerequisite" is probably not a blocker.** ChromeOS
  exposes the Crostini home directory to the Files app as "Linux files" by
  default; that is host-side and needs no "Share with Linux". Moving a
  screenshot in is drag-and-drop today.
- **`SnapmarkCore/Geometry.swift` uses `CGRect.integral`**, which is not
  confirmed present in swift-corelibs-foundation.
- **Line counts:** `Snapmark/` is **1,702** lines (this doc says ~1,500);
  `SnapmarkCore/` is 662, of which the portable trio is 353 (the ~350 estimate
  was right); tests are 370.

### On the recommendation

The framing of A as "a rewrite in TypeScript" is what made it look expensive,
and that framing was self-inflicted. The capability that matters
(`getDisplayMedia` + canvas + `ClipboardItem`) needs no build step, package
manager, bundler, or second release pipeline — roughly 400–600 lines of plain JS
in a single static HTML file, servable from GitHub Pages. `SnapmarkCore`'s
geometry and hit-testing transliterate near-directly, and `ImageExporter.draw`
maps almost line-for-line onto Canvas 2D.

Even so, the decision is C. For a solo project, a second language and a second
release pipeline is real ongoing cost against a need that may already be met:
ChromeOS's built-in screenshot tool captures to clipboard, and the Gallery app
has had crop/text/pen annotation for years. Confirming that on the host is the
five-minute check worth doing before building anything.

**B is the trap** and should not be revived: ~1,500 new UI lines *plus* a Cairo
rewrite of `ImageExporter` *plus* Linux packaging *plus* an unparseable manifest
to fix first — the most effort of any option, to ship something that no longer
does what Snapmark is for. The code-reuse argument is reuse of 353 lines; that
is not a reason to write 1,700 more.

### Unrelated environment note

`sommelier-x@0`/`@1` are stuck in `activating start`.
`journalctl --user -u sommelier-x@0.service` shows Xwayland failing with
`(EE) could not connect to wayland server`, systemd timing out the unit after
90s, and a restart counter at 44 — a live restart loop respawning Xwayland every
90 seconds on a 2-core box, not simply "X11 is dead". The fix is restarting the
Crostini VM. It would not have unblocked any port regardless: rootless
Xwayland's root window never contains host content, so `xwd -root` was never a
path.
