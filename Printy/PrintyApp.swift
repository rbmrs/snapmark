import AppKit
import SwiftUI

@main
struct PrintyApp: App {
    @NSApplicationDelegateAdaptor(PrintyAppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra("Printy", systemImage: "viewfinder") {
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

            Button("Quit Printy") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }

        Settings {
            SettingsView(model: model)
        }
    }
}

final class PrintyAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }
}
