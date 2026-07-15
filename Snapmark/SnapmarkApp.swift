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

            if !model.historyManager.entries.isEmpty {
                Menu("History") {
                    ForEach(model.historyManager.entries) { entry in
                        Button {
                            model.copyFromHistory(id: entry.id)
                        } label: {
                            HStack(spacing: 8) {
                                if let thumbData = model.historyManager.thumbnailData(for: entry.id),
                                   let nsImage = NSImage(data: thumbData) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .frame(width: 32, height: 20)
                                }
                                Text(entry.date.formatted(date: .omitted, time: .shortened))
                                if model.lastCopiedFromHistoryID == entry.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Clear History") {
                        model.clearHistory()
                    }
                }
            }

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
