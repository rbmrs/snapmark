import AppKit
import SwiftUI

@main
struct SnapmarkApp: App {
    @NSApplicationDelegateAdaptor(SnapmarkAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Snapmark", systemImage: "viewfinder") {
            // The shortcut is shown in the title (not as a .keyboardShortcut) so
            // it always reflects the configured global hotkey, and so it can't
            // shadow the hotkey recorder while a new shortcut is being typed.
            Button("Capture Area  \(model.hotKey.displayString)") {
                model.startCapture()
            }
            .disabled(model.isCapturing)

            Divider()

            Button("Settings…") {
                WindowManager.shared.showSettings(model: model)
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit Snapmark") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}

final class SnapmarkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        let model = AppModel.shared
        model.start()
        if !model.hasCompletedOnboarding {
            WindowManager.shared.showOnboarding(model: model)
        }
    }
}
