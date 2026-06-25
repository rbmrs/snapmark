import AppKit
import SwiftUI

@main
struct SnapmarkApp: App {
    @NSApplicationDelegateAdaptor(SnapmarkAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Snapmark", systemImage: "viewfinder") {
            Button("Capture Area") {
                model.startCapture()
            }
            .keyboardShortcut("4", modifiers: [.option, .shift])
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
