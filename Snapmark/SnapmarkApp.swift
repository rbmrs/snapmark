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

            SettingsLink {
                Text("Settings…")
            }

            Divider()

            Button("Quit Snapmark") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class SnapmarkAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
