# Snapmark — Task Backlog

Findings from the 2026-08-02 code review, plus the ChromeOS/Crostini port study
(`docs/chromeos-port.md`). Reviewed 2026-08-02 by two agents that re-read the
cited code and re-tested the ChromeOS environment; their corrections are folded
in below. Ordered by impact.

> **Status 2026-08-02:** everything in *Do first* and *Worth doing* is
> implemented **but unverified** — there is no Swift toolchain on the dev
> machine (Crostini/Linux; `swiftlang` isn't installed and `Package.swift`
> requires tools 6.1 vs Debian's 6.0.3). Nothing below was compiled or run.
> The new CI workflow is what will actually check it — **watch the first CI
> run** before trusting any of it. Swift 6 mode was deliberately *not* done for
> the same reason.

## Do first

- [x] **CI never runs the tests** — `.github/workflows/release.yml` is the only
  workflow, is tag-triggered, and runs `package-release.sh`, which builds but
  never runs `swift test` or `swift run SnapmarkVerification`. 285 lines of tests
  (58+62+90+75) execute only when someone remembers to locally. Add a
  `push`/`pull_request` workflow on `macos-15`:
  `swift build -Xswiftc -warnings-as-errors && swift test && swift run SnapmarkVerification`.
  Keep **both** test lines — see the `SnapmarkVerification` item for why they
  aren't redundant. Consider gating the release job on it.
  *Best value-per-effort on the list, and nothing else here is safe to change
  until something checks those tests.*

- [x] **Auto-updater can trap the app in a relaunch loop** —
  `Snapmark/AppModel.swift:200-230`. Worse than originally written. `start()`
  calls `checkForUpdates()` unconditionally at `:43` (24h timer at `:44-48`).
  The upgrade at `:211` is `_ = AppModel.runShell(...)` — exit status discarded,
  and `runShell` (`:240-255`) sends stderr to `/dev/null` and never checks
  `terminationStatus`. `finishUpdateCheck` then relaunches based on `isOutdated`,
  which was computed *before* the upgrade ran (`:209`). So a persistently failing
  `brew upgrade --cask snapmark` — plausible, given the cask needs `brew trust`
  on Homebrew 6.0+ and has a `postflight` `xattr` step (`Casks/snapmark.rb:34-38`)
  — yields: relaunch → `start()` → still outdated → upgrade fails → relaunch.
  A menu-bar app the user can't get into Settings to stop.
  Minimum fix: check the upgrade's exit status; never relaunch on a failed
  upgrade; require a click to relaunch. Separately, `brew update --quiet` at
  `:207` refreshes *every* tap on every launch — drop it, or run it only on the
  24h timer / a manual button. Fold in the two items marked *(fold into
  updater)* below while in this file.

- [x] **Cask `zap` leaves screenshots on disk** — `Casks/snapmark.rb:40` (not
  `:38`; that's the `end` of `postflight`). `zap trash:` lists only the prefs
  plist, but history writes full-resolution PNGs to
  `~/Library/Application Support/com.rbm.snapmark/History`
  (`SnapmarkCore/HistoryManager.swift`, the `com.rbm.snapmark` path). Zap the whole
  directory, not just `History`. **Edit `scripts/package-release.sh:74`** — the
  heredoc there is authoritative and `release.yml:76` copies it over
  `Casks/snapmark.rb`, so a hand-edit to the cask is overwritten on the next
  release. Mirror it into `Casks/snapmark.rb:40` too. Note `zap` also can't
  undo the `SMAppService` login-item registration.

## Worth doing

- [x] **`HistoryManager` has zero tests and is hard to test** —
  `SnapmarkCore/HistoryManager.swift:19-29`. Newest feature (commit `21cb69b`),
  151 lines of file I/O, and `init()` hardcodes the real Application Support path
  behind a `.first!` force-unwrap (`:21`). Inject the base URL
  (`init(baseURL: URL = <default>)`) — ~5 lines, kills the force-unwrap, unlocks
  temp-dir tests. The logic actually worth testing is manifest/orphan
  reconciliation (`:74-115`), especially `cleanupOrphans`'s
  `replacingOccurrences(of: "_thumb.png", ...)` string surgery at `:108-110` —
  the kind of thing that quietly deletes the wrong file.
  Carry the `saveToHistory` `try?` fix (below) in with it.

- [x] **`saveToHistory` swallows failures** — `Snapmark/AppModel.swift:107` uses
  `try?`. Lower blast radius than it looks: `CaptureCoordinator.swift:74` puts
  the image on the clipboard *before* `saveToHistory` at `:76`, so the capture
  itself is never lost. Real failure modes are disk-full and thumbnail
  generation. Bundle with the `HistoryManager` item.

- [x] **Two near-identical pasteboard writers** —
  `SnapmarkCore/ImageExporter.swift:79` and `:90`. Both are currently *correct* —
  this is duplication, not a bug — but `:90` carries the double-paste regression
  note at `:96-100` and `:79` has none, so `:79` is the one someone will edit
  wrong. Have `writeToPasteboard(_ image:)` encode to PNG and delegate. ~10
  minutes, protects a real past regression.

- [x] **Document why `SnapmarkVerification` duplicates `SnapmarkCoreTests`** —
  and the rationale is discoverable, not lost: `scripts/build-app.sh:18-21` shows
  the project deliberately supports plain Command Line Tools, while `swift test`
  on macOS requires full Xcode's `xctest`. `SnapmarkVerification` is the
  XCTest-free smoke test. The actual gap is that `README.md:38-40` documents
  `swift run SnapmarkVerification` and **never mentions `swift test`**. Fix =
  one sentence in `SnapmarkVerification/main.swift` + add `swift test` to the
  README. 5 minutes, and it's the context most likely to be lost.

- [ ] **Swift 6 language mode is *not* close to free** — `Package.swift:36` (not
  `:35`) pins `swiftLanguageModes: [.v5]`. The original "looks close to free"
  read was wrong; there are at least three hard errors under Swift 6:
  `AppModel.swift:120` (`DispatchQueue.main.asyncAfter` closure touching
  MainActor-isolated `lastCopiedFromHistoryID` from a nonisolated context),
  `HotKeyManager.swift:87` (captures non-`Sendable` `HotKeyManager` in a
  `@Sendable` closure — the class at `:56` has no isolation annotation), and
  `CaptureCoordinator.swift:228` (calls MainActor-isolated `close()` from a
  nonisolated closure). ~an hour: move to `Task { @MainActor in }` and mark
  `HotKeyManager @MainActor`.

## Small / conditional

- [x] **`relaunch()` interpolates paths into `/bin/sh -c`** —
  `Snapmark/AppModel.swift:175-193`. **Not a vulnerability**, as originally
  framed: `bundlePath` is `Bundle.main.bundlePath`, which under the only
  supported install path (Homebrew cask, `app "Snapmark.app"`) is
  `/Applications/Snapmark.app`. Anyone controlling that path already controls
  the binary. The genuine, small bug is breakage — including
  `case "$path" in *.app)` at `:185` glob-matching the path. Pass paths as
  `"$1"`/`"$2"`, or drop the shell for `NSWorkspace.openApplication`.
  *(fold into updater)*

- [x] **`updateStatusMessage` is never cleared** — `Snapmark/AppModel.swift:201`
  (set at `:201/204/221/224`, never nil'd; rendered at `SettingsView.swift:47-51`).
  Visible only inside Settings, but "Snapmark is up to date." can be 24h stale.
  *(fold into updater)*

- [x] **`InstallEventHandler` status discarded** —
  `Snapmark/HotKeyManager.swift:70`. Overstated originally: there's a
  "Capture Area" menu item at `SnapmarkApp.swift:14`, so a failed handler
  degrades to menu-only capture, not a dead app. Worth an `assertionFailure` and
  a surfaced error, nothing more.

- [x] **Bundle ID / support-dir mismatch — keeping it, deliberately.**
  `Snapmark/Info.plist:9-10` says `com.rafaelbm.Snapmark`; history writes to
  `com.rbm.snapmark` (`SnapmarkCore/HistoryManager.swift:36`). Neither side moves:
  changing the bundle ID revokes every existing user's Screen Recording grant
  (`scripts/build-app.sh:54-55` pins it in the codesign designated requirement,
  and TCC keys on that), and changing the directory strands existing history.
  Uninstall is already clean — `zap` trashes the whole `com.rbm.snapmark`
  directory (`scripts/package-release.sh:78`, mirrored at `Casks/snapmark.rb:44`).
  A NOTE at `HistoryManager.swift:30-34` records this in-code; don't reopen it.

## Follow-ups opened by the 2026-08-02 implementation pass

- [x] **New test file isn't in the Xcode project.** Registered
  `SnapmarkCoreTests/HistoryManagerTests.swift` in `project.pbxproj`. Turned up
  a second gap while doing it: **`SnapmarkCore/HistoryManager.swift` itself was
  also missing from the Xcode project** — no file reference, not in the
  framework's sources phase. `swift test` hid both, because SwiftPM globs by
  directory. Registering only the test would have converted a silently-skipped
  test into an Xcode compile failure, so both files were added.
  Validated structurally only (no Xcode here): the plist parses, 94 objects, no
  dangling references, and each target resolves to the expected source list.
  **Confirm on the first Xcode open.**

- [ ] **`release.yml` still doesn't depend on CI.** `needs:` only works between
  jobs in one workflow file, so gating means either duplicating build/test as a
  second job in `release.yml` or converting `ci.yml` to `workflow_call` with a
  caller job. Both restructure the release path, which can't be tested here.
  Mitigation for now: tag pushes run `scripts/build-app.sh` with
  `-Xswiftc -warnings-as-errors`, so a broken *build* still fails the release —
  a broken *test* would not.

- [x] **`addEntry` leaks an orphan PNG when thumbnail generation fails.** Fixed
  by reordering rather than compensating: `generateThumbnail` works purely from
  the in-memory `pngData`, so it now runs *before* any disk work — a throw leaves
  nothing behind, and no directory is created for a call that can't succeed. The
  one window reordering can't close (an I/O failure between the two writes) is
  handled by a `do/catch` that calls `removeFiles(for:)` and rethrows.
  `testAddEntryWithNonImageDataThrowsAndRecordsNoEntry` was flipped from pinning
  the leak to asserting its absence.

- [ ] **`cleanupOrphans` deletes *every* unrecognised file in the History
  directory**, not just stale captures — including anything a user or another
  tool drops there. Captured as a characterisation test
  (`testCleanupDeletesEveryUnrecognisedFileInTheHistoryDirectory`, asserts
  current behaviour, not desired behaviour). Decide whether to narrow it to
  `*.png` / `*_thumb.png`.

- [ ] **Behaviour change to confirm:** when Carbon handler installation fails,
  `applyHotKey` now surfaces the error and therefore skips `hotKey.save()`, so
  the user's chosen shortcut isn't persisted. Accurate (no shortcut can work in
  that state) but it goes slightly beyond pure diagnostics — flip it to
  save-then-report if you'd rather.

## Dropped on review

- ~~**Corrupt stored hotkey has no recovery**~~ — `HotKeyManager.swift:23`. The
  described failure is near-unreachable: `save()` is only called from
  `AppModel.swift:66-68` *after* a successful `register()`, so a bad value
  requires manual `defaults` tampering. And it isn't permanent — `hotKeyError`
  shows at `SettingsView.swift:20`, capture still works from the menu, one click
  fixes it. Add 3 lines of defensive validation in `load()` only if already in
  the file.
- ~~**Unbounded undo stack**~~ — `CaptureSession.swift:27`. Reset per session at
  `:39`; `checkpoint()` fires once per *gesture*, not per mouse-move
  (`OverlayView.swift:135-138` guards with `dragCheckpointed`). Bounded by ~10
  actions in a 30-second session.

## ChromeOS / Crostini — dropped 2026-08-02

Not pursuing a ChromeOS port. Snapmark stays macOS-only (option **C**). The
study and the review's corrections to it are preserved in
`docs/chromeos-port.md`; nothing here is an open task.

<details>
<summary>Why, in short</summary>

Screen capture and global hotkeys are both impossible inside Crostini
(independently re-verified: no capture protocol in sommelier, no `/dev/dri`,
`/dev/fb0` or `/dev/input`, and the only installed portal backend advertises
neither Screenshot nor ScreenCast). Option **B** (Linux annotate-only editor)
was additionally dead on arrival — `Package.swift` requires tools 6.1 while
Debian ships 6.0.3, so the manifest won't even parse, and `ImageExporter` is
CoreGraphics-bound, which is a Cairo rewrite rather than a shim. Option **A**
(PWA) is technically viable but imports a second toolchain and release pipeline
into a solo project. If the itch ever returns, the cheapest form is a single
static HTML page (`getDisplayMedia` + canvas + `ClipboardItem`, no build step),
and it's worth first checking whether ChromeOS's built-in screenshot tool plus
the Gallery app's crop/text/pen annotation already covers the need at zero cost.

</details>
