import AppKit
import Combine
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

    private let hotKeyManager = HotKeyManager()
    private lazy var captureCoordinator = CaptureCoordinator(model: self)
    private var didStart = false

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
}
