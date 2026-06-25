import Carbon.HIToolbox
import Foundation

struct HotKey: Equatable {
    static let defaultValue = HotKey(
        keyCode: UInt32(kVK_ANSI_4),
        modifiers: UInt32(optionKey | shiftKey)
    )

    var keyCode: UInt32
    var modifiers: UInt32

    var displayString: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        value += KeyCodeNames.name(for: keyCode)
        return value
    }

    static func load(defaults: UserDefaults = .standard) -> HotKey {
        guard defaults.object(forKey: "hotKey.keyCode") != nil else {
            return .defaultValue
        }
        return HotKey(
            keyCode: UInt32(defaults.integer(forKey: "hotKey.keyCode")),
            modifiers: UInt32(defaults.integer(forKey: "hotKey.modifiers"))
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(Int(keyCode), forKey: "hotKey.keyCode")
        defaults.set(Int(modifiers), forKey: "hotKey.modifiers")
    }
}

enum HotKeyError: LocalizedError {
    case missingModifier
    case registrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .missingModifier:
            return "Choose a shortcut containing Command, Option, or Control."
        case .registrationFailed(let status):
            if status == eventHotKeyExistsErr {
                return "That shortcut is already used by another application."
            }
            return "The shortcut could not be registered (error \(status))."
        }
    }
}

final class HotKeyManager {
    var onPress: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let signature: OSType = 0x5052_4E54 // PRNT
    private let hotKeyID: UInt32 = 1

    init() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &identifier
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if identifier.signature == manager.signature && identifier.id == manager.hotKeyID {
                    DispatchQueue.main.async {
                        manager.onPress?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            pointer,
            &eventHandlerRef
        )
    }

    deinit {
        unregister()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ hotKey: HotKey) throws {
        let meaningfulModifiers = UInt32(cmdKey | optionKey | controlKey)
        guard hotKey.modifiers & meaningfulModifiers != 0 else {
            throw HotKeyError.missingModifier
        }

        unregister()
        let identifier = EventHotKeyID(signature: signature, id: hotKeyID)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            identifier,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        guard status == noErr else {
            hotKeyRef = nil
            throw HotKeyError.registrationFailed(status)
        }
    }

    /// Temporarily removes the global hotkey — used while the user is typing a
    /// new shortcut so pressing the current one is recorded, not fired.
    func suspend() {
        unregister()
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

enum KeyCodeNames {
    private static let names: [UInt32: String] = [
        UInt32(kVK_ANSI_A): "A", UInt32(kVK_ANSI_B): "B", UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D", UInt32(kVK_ANSI_E): "E", UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G", UInt32(kVK_ANSI_H): "H", UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J", UInt32(kVK_ANSI_K): "K", UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M", UInt32(kVK_ANSI_N): "N", UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P", UInt32(kVK_ANSI_Q): "Q", UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S", UInt32(kVK_ANSI_T): "T", UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V", UInt32(kVK_ANSI_W): "W", UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y", UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0", UInt32(kVK_ANSI_1): "1", UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3", UInt32(kVK_ANSI_4): "4", UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6", UInt32(kVK_ANSI_7): "7", UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab", UInt32(kVK_Escape): "Escape"
    ]

    static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}
