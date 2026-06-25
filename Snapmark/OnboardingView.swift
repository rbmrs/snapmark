import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            VStack(spacing: 12) {
                screenRecordingRow
                launchAtLoginRow
                shortcutRow
            }
            .padding(24)

            Divider()
            footer
        }
        .frame(width: 460)
        // Screen Recording is granted out of process; re-check when the user
        // returns to Snapmark (e.g. after allowing it in System Settings).
        .onReceive(
            NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            model.refreshScreenRecording()
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "viewfinder")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.tint)
            Text("Welcome to Snapmark")
                .font(.title).bold()
            Text("Snap a region of your screen, mark it up with rectangles and arrows, then copy it — all from the menu bar.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 28)
        .padding(.horizontal, 28)
    }

    private var screenRecordingRow: some View {
        row(
            icon: "camera.viewfinder",
            title: "Screen Recording",
            detail: "Required so Snapmark can capture your screen."
        ) {
            if model.screenRecordingGranted {
                Label("Granted", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.green)
            } else {
                Button("Grant") {
                    WindowManager.shared.yieldFloating()
                    model.requestScreenRecording()
                }
            }
        }
    }

    private var launchAtLoginRow: some View {
        row(
            icon: "power",
            title: "Launch at Login",
            detail: "Start Snapmark automatically when you log in. Optional."
        ) {
            Toggle(
                "",
                isOn: Binding(
                    get: { model.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
    }

    private var shortcutRow: some View {
        row(
            icon: "command",
            title: "Capture Shortcut",
            detail: "Press this anytime to start a capture. Change it in Settings."
        ) {
            Text(model.hotKey.displayString)
                .font(.system(.body, design: .monospaced).weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if !model.screenRecordingGranted {
                Text("After allowing Screen Recording in System Settings, choose Quit & Reopen to finish enabling capture.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Skip") { finish() }
                    .buttonStyle(.link)
                Spacer()
                if !model.screenRecordingGranted {
                    Button("Quit & Reopen") { model.relaunch() }
                }
                Button("Get Started") { finish() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }

    private func row(
        icon: String,
        title: String,
        detail: String,
        @ViewBuilder accessory: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            accessory()
        }
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func finish() {
        model.completeOnboarding()
        onFinish()
    }
}
