import AppKit
import SwiftUI

/// Owns Snapmark's auxiliary windows (Settings, Onboarding). Because Snapmark is
/// an accessory (menu-bar) app, activation alone can't reliably pull a window in
/// front of the frontmost app (e.g. Safari/Terminal) on recent macOS — the
/// window ends up hidden behind it. So these windows use the floating level and
/// the active-Space collection behavior, which guarantees they surface on top
/// wherever the user is, in addition to activating the app and ordering front.
@MainActor
final class WindowManager {
    static let shared = WindowManager()

    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    private init() {}

    func showSettings(model: AppModel) {
        model.refreshScreenRecording()
        if settingsWindow == nil {
            settingsWindow = makeWindow(
                title: "Snapmark Settings",
                content: SettingsView(model: model)
            )
        }
        present(settingsWindow)
    }

    func showOnboarding(model: AppModel) {
        model.refreshScreenRecording()
        if onboardingWindow == nil {
            onboardingWindow = makeWindow(
                title: "Welcome to Snapmark",
                content: OnboardingView(model: model) { [weak self] in
                    self?.onboardingWindow?.close()
                }
            )
        }
        present(onboardingWindow)
        // Auto-present only once; later access is via the menu/Settings.
        model.completeOnboarding()
    }

    private func makeWindow(title: String, content: some View) -> NSWindow {
        // The window sizes to the hosting view's fitting size, so each hosted
        // view (SettingsView, OnboardingView) carries an explicit frame.
        let window = NSWindow(contentViewController: NSHostingController(rootView: content))
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.center()
        return window
    }

    /// Drops the auxiliary windows below other apps so a window we send the user
    /// to — e.g. the System Settings Privacy pane during the Screen Recording
    /// grant flow — isn't hidden underneath our floating window. They float again
    /// the next time they're presented.
    func yieldFloating() {
        settingsWindow?.level = .normal
        onboardingWindow?.level = .normal
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        window.level = .floating
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
