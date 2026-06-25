import AppKit
import Carbon.HIToolbox
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Capture shortcut") {
                HotKeyRecorder(
                    hotKey: model.hotKey,
                    onChange: { model.applyHotKey($0) },
                    onBeginRecording: { model.suspendHotKey() },
                    onEndRecording: { model.resumeHotKey() }
                )
                .frame(width: 150, height: 28)
            }

            if let error = model.hotKeyError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Toggle(
                "Launch Snapmark at login",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )

            if let error = model.launchAtLoginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            LabeledContent("Screen Recording") {
                if model.screenRecordingGranted {
                    Label("Granted", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Grant…") {
                        WindowManager.shared.yieldFloating()
                        model.requestScreenRecording()
                    }
                }
            }

            Text("Snapmark needs Screen Recording permission to capture your screen. It does not record audio or require Accessibility.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 440, height: 260)
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshScreenRecording()
        }
    }
}

struct HotKeyRecorder: NSViewRepresentable {
    let hotKey: HotKey
    let onChange: (HotKey) -> Void
    let onBeginRecording: () -> Void
    let onEndRecording: () -> Void

    func makeNSView(context: Context) -> HotKeyRecorderView {
        let view = HotKeyRecorderView()
        view.onChange = onChange
        view.onBeginRecording = onBeginRecording
        view.onEndRecording = onEndRecording
        view.hotKey = hotKey
        return view
    }

    func updateNSView(_ nsView: HotKeyRecorderView, context: Context) {
        nsView.onChange = onChange
        nsView.onBeginRecording = onBeginRecording
        nsView.onEndRecording = onEndRecording
        nsView.hotKey = hotKey
    }
}

final class HotKeyRecorderView: NSView {
    var onChange: ((HotKey) -> Void)?
    var onBeginRecording: (() -> Void)?
    var onEndRecording: (() -> Void)?
    var hotKey: HotKey = .defaultValue {
        didSet { needsDisplay = true }
    }
    private var isRecording = false

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard !isRecording else { return }
        isRecording = true
        onBeginRecording?()
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == UInt16(kVK_Escape) {
            endRecording()
            return
        }

        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var carbonModifiers: UInt32 = 0
        if modifiers.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if modifiers.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if modifiers.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if modifiers.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        // Apply the new shortcut first, then end recording (which re-registers
        // whatever the current hotkey is now).
        onChange?(HotKey(keyCode: UInt32(event.keyCode), modifiers: carbonModifiers))
        endRecording()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { endRecording() }
        return super.resignFirstResponder()
    }

    private func endRecording() {
        guard isRecording else { return }
        isRecording = false
        onEndRecording?()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 6, yRadius: 6)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.16) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.lineWidth = 1
        path.stroke()

        let text = isRecording ? "Type shortcut…" : hotKey.displayString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = text.size(withAttributes: attributes)
        text.draw(
            at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2),
            withAttributes: attributes
        )
    }
}
