import AppKit
import CoreGraphics
import Foundation
import SnapmarkCore
import ScreenCaptureKit

struct CapturedDisplay {
    let screen: NSScreen
    let image: CGImage
}

@MainActor
final class CaptureCoordinator {
    private unowned let model: AppModel
    private var overlays: [OverlayWindowController] = []
    private weak var activeOverlay: OverlayView?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard overlays.isEmpty else { return }
        guard shouldAttemptScreenCapture() else {
            model.captureDidFinish()
            return
        }

        Task {
            do {
                let captures = try await captureAllDisplays()
                guard !captures.isEmpty else {
                    throw CaptureError.noDisplays
                }
                presentOverlays(for: captures)
            } catch {
                // ScreenCaptureKit may fail immediately while macOS is showing
                // its native permission prompt. Avoid stacking another alert
                // on top of the system-owned flow.
                if CGPreflightScreenCaptureAccess() {
                    showCaptureError(error)
                }
                finishSession()
            }
        }
    }

    func didChooseFirstCorner(in overlay: OverlayView) {
        activeOverlay = overlay
        for controller in overlays {
            controller.overlayView.acceptsSelectionInput = controller.overlayView === overlay
        }
    }

    func didConfirmCrop(in overlay: OverlayView) {
        activeOverlay = overlay
        for controller in overlays where controller.overlayView !== overlay {
            controller.hide()
        }
        overlay.acceptsSelectionInput = true
        overlay.window?.makeKeyAndOrderFront(nil)
        overlay.window?.makeFirstResponder(overlay)
    }

    func copyAndFinish(from overlay: OverlayView) {
        guard let cropRect = overlay.session.cropRect else { return }
        do {
            let image = try ImageExporter.render(
                sourceImage: overlay.capturedImage,
                displayPointSize: overlay.bounds.size,
                cropRect: cropRect,
                annotations: overlay.session.annotations
            )
            try ImageExporter.writeToPasteboard(image)
            finishSession()
        } catch {
            showCaptureError(error)
        }
    }

    func cancel() {
        finishSession()
    }

    private func shouldAttemptScreenCapture() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        let defaults = UserDefaults.standard
        let requestKey = "permissions.didRequestScreenCapture"
        if !defaults.bool(forKey: requestKey) {
            defaults.set(true, forKey: requestKey)
            _ = CGRequestScreenCaptureAccess()

            // macOS owns the first-run permission prompt. Do not place a
            // second Snapmark alert underneath it; the user can invoke capture
            // again after granting access.
            return false
        }

        // The preflight result can stay stale after the user grants access.
        // Let ScreenCaptureKit attempt the capture; only show our guidance if
        // the real capture operation fails while preflight still says denied.
        return true
    }

    private func captureAllDisplays() async throws -> [CapturedDisplay] {
        let content = try await shareableContent()
        let screensByID: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    return nil
                }
                return (CGDirectDisplayID(number.uint32Value), screen)
            }
        )

        var captures: [CapturedDisplay] = []
        for display in content.displays {
            guard let screen = screensByID[display.displayID] else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = Int(screen.frame.width * screen.backingScaleFactor)
            configuration.height = Int(screen.frame.height * screen.backingScaleFactor)
            configuration.showsCursor = false
            configuration.capturesAudio = false
            configuration.scalesToFit = true
            guard let image = try await captureImage(filter: filter, configuration: configuration) else {
                continue
            }
            captures.append(CapturedDisplay(screen: screen, image: image))
        }
        return captures
    }

    private func shareableContent() async throws -> SCShareableContent {
        try await withCheckedThrowingContinuation { continuation in
            SCShareableContent.getExcludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            ) { content, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let content {
                    continuation.resume(returning: content)
                } else {
                    continuation.resume(throwing: CaptureError.noDisplays)
                }
            }
        }
    }

    private func captureImage(
        filter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage? {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: image)
                }
            }
        }
    }

    private func presentOverlays(for captures: [CapturedDisplay]) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        overlays = captures.map { capture in
            OverlayWindowController(capture: capture, coordinator: self)
        }
        overlays.forEach { $0.show() }
    }

    private func finishSession() {
        let controllers = overlays
        controllers.forEach { $0.hide() }
        overlays.removeAll(keepingCapacity: true)
        activeOverlay = nil
        model.captureDidFinish()

        // AppKit may still be dispatching a mouse/key event to an overlay. Keep
        // the windows alive until the next run-loop turn to avoid releasing an
        // event target from inside its own callback.
        DispatchQueue.main.async {
            controllers.forEach { $0.close() }
        }
    }

    private func showCaptureError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Snapmark Could Not Capture the Screen"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum CaptureError: LocalizedError {
    case noDisplays

    var errorDescription: String? {
        "No capturable displays were found."
    }
}

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class OverlayWindowController {
    let window: OverlayWindow
    let overlayView: OverlayView

    init(capture: CapturedDisplay, coordinator: CaptureCoordinator) {
        window = OverlayWindow(
            contentRect: capture.screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: capture.screen
        )
        overlayView = OverlayView(image: capture.image, coordinator: coordinator)

        window.contentView = overlayView
        window.level = .screenSaver
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .black
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.acceptsMouseMovedEvents = true
        window.setFrame(capture.screen.frame, display: false)
    }

    func show() {
        window.orderFrontRegardless()
        window.makeKey()
        window.makeFirstResponder(overlayView)
    }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    func hide() {
        window.orderOut(nil)
    }
}
