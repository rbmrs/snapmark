import AppKit
import Combine
import CoreGraphics
import Foundation
import ServiceManagement
import SnapmarkCore
import os

private let logger = Logger(subsystem: "com.rafaelbm.Snapmark", category: "AppModel")

/// Result of a shell invocation. `output` carries stdout and stderr interleaved:
/// Homebrew reports its failures on stderr, and those are exactly the lines worth
/// showing the user when an upgrade doesn't take.
private struct ShellResult: Sendable {
    let status: Int32
    let output: String

    var succeeded: Bool { status == 0 }

    /// Last non-empty output line, clipped — enough to identify a failure without
    /// spilling a full Homebrew log into a settings label.
    var lastLine: String {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let last = lines.last(where: { !$0.isEmpty }) else { return "" }
        return last.count > 120 ? String(last.prefix(120)) + "…" : last
    }
}

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var isCapturing = false
    @Published var hotKey: HotKey = HotKey.load()
    @Published var hotKeyError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchAtLoginError: String?
    @Published var screenRecordingGranted = CGPreflightScreenCaptureAccess()
    @Published private(set) var updateStatusMessage: String?
    @Published private(set) var updateAvailable = false
    @Published private(set) var updateReadyToRelaunch = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var isInstallingUpdate = false

    let historyManager = HistoryManager()
    @Published private(set) var lastCopiedFromHistoryID: UUID?

    private let hotKeyManager = HotKeyManager()
    private lazy var captureCoordinator = CaptureCoordinator(model: self)
    private var didStart = false
    private var pendingRelaunch = false
    private let updateCheckInterval: TimeInterval = 86_400
    /// How long a purely informational update message sticks around. Prompts the
    /// user can act on are set without a lifetime and stay put.
    private let statusMessageLifetime: TimeInterval = 30
    private var updateStatusToken = 0

    private let onboardingKey = "onboarding.completed"
    private let didRequestScreenCaptureKey = "permissions.didRequestScreenCapture"

    private init() {}

    func start() {
        guard !didStart else { return }
        didStart = true
        hotKeyManager.onPress = { [weak self] in
            Task { @MainActor in
                self?.startCapture()
            }
        }
        applyHotKey(hotKey)
        // Detection only — installing and relaunching always wait for the user.
        // The launch check skips the tap refresh; the daily one pays for it.
        checkForUpdates(refreshingTaps: false)
        Timer.scheduledTimer(withTimeInterval: updateCheckInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForUpdates()
            }
        }
    }

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        captureCoordinator.start()
    }

    func captureDidFinish() {
        isCapturing = false
        if pendingRelaunch {
            relaunch()
        }
    }

    func applyHotKey(_ candidate: HotKey) {
        do {
            try hotKeyManager.register(candidate)
            hotKey = candidate
            hotKey.save()
            hotKeyError = nil
        } catch {
            hotKeyError = error.localizedDescription
        }
    }

    /// Called when the shortcut recorder starts capturing keystrokes: drop the
    /// global hotkey so the user can re-enter the current shortcut without
    /// triggering a capture.
    func suspendHotKey() {
        hotKeyManager.suspend()
    }

    /// Called when recording ends. Re-registers the current shortcut — which is
    /// the newly chosen one after a successful change, or the previous one if the
    /// user cancelled or the new shortcut couldn't be registered.
    func resumeHotKey() {
        try? hotKeyManager.register(hotKey)
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchAtLoginError = error.localizedDescription
        }
    }

    // MARK: - History

    func saveToHistory(pngData: Data) {
        do {
            try historyManager.addEntry(pngData: pngData)
        } catch {
            // The capture itself is safe — CaptureCoordinator writes it to the
            // pasteboard before calling us — so a failed save costs the history
            // entry and nothing else. Log it rather than interrupt the user.
            logger.error("Failed to add screenshot to history: \(error.localizedDescription, privacy: .public)")
        }
        objectWillChange.send()
    }

    func clearHistory() {
        historyManager.clearAll()
        objectWillChange.send()
    }

    func copyFromHistory(id: UUID) {
        guard let pngData = historyManager.fullImageData(for: id) else { return }
        ImageExporter.writeToPasteboard(pngData: pngData)
        lastCopiedFromHistoryID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.lastCopiedFromHistoryID == id {
                self?.lastCopiedFromHistoryID = nil
            }
        }
        objectWillChange.send()
    }

    // MARK: - Onboarding & permissions

    var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: onboardingKey)
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: onboardingKey)
    }

    /// Re-reads the live Screen Recording status. Granting happens out of process
    /// (the system prompt or System Settings), so the onboarding view polls this.
    func refreshScreenRecording() {
        let granted = CGPreflightScreenCaptureAccess()
        if granted != screenRecordingGranted {
            screenRecordingGranted = granted
        }
    }

    /// Drives the Screen Recording grant flow: the first request shows the system
    /// prompt; afterwards we send the user to the System Settings pane, since
    /// macOS only presents the prompt once.
    func requestScreenRecording() {
        if CGPreflightScreenCaptureAccess() {
            screenRecordingGranted = true
            return
        }

        let defaults = UserDefaults.standard
        if defaults.bool(forKey: didRequestScreenCaptureKey) {
            openScreenRecordingSettings()
        } else {
            defaults.set(true, forKey: didRequestScreenCaptureKey)
            _ = CGRequestScreenCaptureAccess()
        }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Relaunches Snapmark. ScreenCaptureKit reads a process-cached Screen
    /// Recording status, so after the user grants access a restart is the
    /// reliable way to pick it up. Waits for this instance to exit, then reopens.
    func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let executablePath = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Paths go in as positional arguments rather than interpolated into the
        // script, so quotes, `$` or backticks in the path can't break (or be
        // re-interpreted by) the shell.
        task.arguments = [
            "-c",
            """
            while /bin/kill -0 "$1" >/dev/null 2>&1; do /bin/sleep 0.2; done
            case "$2" in
              *.app) /usr/bin/open "$2" ;;
              *) /usr/bin/nohup "$3" >/dev/null 2>&1 & ;;
            esac
            """,
            "sh", pid, bundlePath, executablePath
        ]
        try? task.run()
        NSApp.terminate(nil)
    }

    // MARK: - Updates

    /// Asks Homebrew whether a newer cask version exists. Detection only: the
    /// install and the relaunch are separate, explicitly user-driven steps, so a
    /// persistently failing `brew upgrade` can't put the app in a
    /// check → upgrade → relaunch loop that a menu-bar app gives the user no way
    /// to break out of.
    ///
    /// `refreshingTaps` runs `brew update` first, which re-fetches every tap over
    /// the network — worth it on the manual and daily paths, too slow for launch.
    func checkForUpdates(refreshingTaps: Bool = true) {
        guard !isCheckingForUpdates, !isInstallingUpdate else { return }
        isCheckingForUpdates = true
        setUpdateStatus("Checking for updates…")
        Task.detached(priority: .utility) {
            guard let brew = AppModel.brewExecutablePath() else {
                await MainActor.run {
                    AppModel.shared.finishUpdateCheck(isOutdated: false, brewMissing: true)
                }
                return
            }
            if refreshingTaps {
                _ = AppModel.runShell("\"\(brew)\" update --quiet")
            }
            // `brew outdated` prints nothing when there's nothing to do; its exit
            // status isn't a reliable signal here, so go by the output.
            let outdated = AppModel.runShell("\"\(brew)\" outdated --cask snapmark")
            let isOutdated = !outdated.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            await MainActor.run {
                AppModel.shared.finishUpdateCheck(isOutdated: isOutdated, brewMissing: false)
            }
        }
    }

    private func finishUpdateCheck(isOutdated: Bool, brewMissing: Bool) {
        isCheckingForUpdates = false
        guard !brewMissing else {
            updateAvailable = false
            setUpdateStatus(
                "Homebrew not found — update Snapmark manually.",
                clearAfter: statusMessageLifetime
            )
            return
        }
        updateAvailable = isOutdated
        if isOutdated {
            // No lifetime: this one is a prompt the user is meant to act on.
            setUpdateStatus("An update is available.")
        } else if updateReadyToRelaunch {
            // Already upgraded on disk this session: Homebrew is right that
            // there's nothing left to install, but this process is still the old
            // build, so keep the relaunch prompt rather than saying "up to date".
            setUpdateStatus("Update installed — relaunch to finish.")
        } else {
            setUpdateStatus("Snapmark is up to date.", clearAfter: statusMessageLifetime)
        }
    }

    /// Installs the pending update. Only ever reached from an explicit user
    /// action; on failure we stop here and say why, and never relaunch.
    func installUpdate() {
        guard updateAvailable, !isInstallingUpdate, !isCheckingForUpdates else { return }
        isInstallingUpdate = true
        setUpdateStatus("Installing update…")
        Task.detached(priority: .utility) {
            guard let brew = AppModel.brewExecutablePath() else {
                await MainActor.run {
                    AppModel.shared.finishInstall(succeeded: false, detail: "Homebrew not found.")
                }
                return
            }
            let result = AppModel.runShell("\"\(brew)\" upgrade --cask snapmark")
            await MainActor.run {
                AppModel.shared.finishInstall(succeeded: result.succeeded, detail: result.lastLine)
            }
        }
    }

    private func finishInstall(succeeded: Bool, detail: String) {
        isInstallingUpdate = false
        guard succeeded else {
            // Leave `updateAvailable` set so the user can retry, but stay put:
            // the upgrade can fail for reasons a restart won't fix (the cask
            // needs `brew trust` on Homebrew 6.0+, and its postflight clears the
            // quarantine xattr), and relaunching on a failure is what used to
            // loop the app forever.
            logger.error("brew upgrade --cask snapmark failed: \(detail, privacy: .public)")
            let suffix = detail.isEmpty ? "" : " (\(detail))"
            setUpdateStatus("Update failed\(suffix). Try: brew upgrade --cask snapmark")
            return
        }
        updateAvailable = false
        updateReadyToRelaunch = true
        setUpdateStatus("Update installed — relaunch to finish.")
    }

    /// Restarts into the freshly installed build. Explicit user action, deferred
    /// until the current capture finishes, since restarting mid-annotation would
    /// drop it.
    func relaunchAfterUpdate() {
        guard updateReadyToRelaunch else { return }
        if isCapturing {
            pendingRelaunch = true
            setUpdateStatus("Relaunching when the current capture finishes…")
        } else {
            relaunch()
        }
    }

    /// Update status is transient UI. A single pending clear, keyed by token, so
    /// a stale "up to date" can never blank out a newer message.
    private func setUpdateStatus(_ message: String?, clearAfter seconds: TimeInterval? = nil) {
        updateStatusToken &+= 1
        let token = updateStatusToken
        updateStatusMessage = message
        guard let seconds else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, self.updateStatusToken == token else { return }
            self.updateStatusMessage = nil
        }
    }

    /// GUI apps don't inherit the shell's PATH, so probe Homebrew's two standard
    /// install locations directly.
    nonisolated private static func brewExecutablePath() -> String? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// Runs `command` and reports how it went. Callers that act on the result —
    /// notably the upgrade — must check `succeeded`; a discarded exit status is
    /// what let a failing upgrade look like a successful one.
    nonisolated private static func runShell(_ command: String) -> ShellResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", command]
        // stdout and stderr share one pipe: we read it to EOF before waiting, so
        // there's no buffer to deadlock on, and Homebrew's diagnostics come along.
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        do {
            try task.run()
        } catch {
            return ShellResult(status: -1, output: error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return ShellResult(
            status: task.terminationStatus,
            output: String(data: data, encoding: .utf8) ?? ""
        )
    }
}
