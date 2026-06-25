import AppKit
import Combine
import CoreGraphics
import Foundation
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var isCapturing = false
    @Published var hotKey: HotKey = HotKey.load()
    @Published var hotKeyError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var launchAtLoginError: String?
    @Published var screenRecordingGranted = CGPreflightScreenCaptureAccess()

    private let hotKeyManager = HotKeyManager()
    private lazy var captureCoordinator = CaptureCoordinator(model: self)
    private var didStart = false

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
    }

    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        captureCoordinator.start()
    }

    func captureDidFinish() {
        isCapturing = false
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
        let path = Bundle.main.bundlePath
        let pid = String(ProcessInfo.processInfo.processIdentifier)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = [
            "-c",
            "while /bin/kill -0 \(pid) >/dev/null 2>&1; do /bin/sleep 0.2; done; /usr/bin/open \"\(path)\""
        ]
        try? task.run()
        NSApp.terminate(nil)
    }
}
