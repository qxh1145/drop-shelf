import AppKit
import Carbon.HIToolbox
import Foundation

struct ShelfActivationShortcut: Codable, Equatable, Sendable {
    static let defaultShortcut = ShelfActivationShortcut(
        keyCode: UInt32(kVK_Space),
        keyLabel: "Space",
        modifierFlags: [.control, .option]
    )
    static let historyShortcut = ShelfActivationShortcut(
        keyCode: UInt32(kVK_ANSI_H),
        keyLabel: "H",
        modifierFlags: [.command, .shift]
    )

    let keyCode: UInt32
    let keyLabel: String
    let modifierRawValue: UInt

    init(
        keyCode: UInt32,
        keyLabel: String,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        self.keyCode = keyCode
        self.keyLabel = keyLabel
        self.modifierRawValue = modifierFlags
            .intersection(Self.supportedModifiers)
            .rawValue
    }

    init?(event: NSEvent) {
        let modifierFlags = event.modifierFlags
            .intersection(Self.supportedModifiers)
        guard !modifierFlags.isEmpty,
              event.keyCode != UInt16(kVK_Escape) else {
            return nil
        }

        let keyLabel = Self.specialKeyLabels[event.keyCode]
            ?? event.charactersIgnoringModifiers?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased()
        guard let keyLabel, !keyLabel.isEmpty else { return nil }

        self.init(
            keyCode: UInt32(event.keyCode),
            keyLabel: keyLabel,
            modifierFlags: modifierFlags
        )
    }

    var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifierRawValue)
    }

    var displayName: String {
        var result = ""
        if modifierFlags.contains(.control) { result += "⌃" }
        if modifierFlags.contains(.option) { result += "⌥" }
        if modifierFlags.contains(.shift) { result += "⇧" }
        if modifierFlags.contains(.command) { result += "⌘" }
        return result + keyLabel
    }

    var carbonModifierFlags: UInt32 {
        var result = 0
        if modifierFlags.contains(.control) { result |= controlKey }
        if modifierFlags.contains(.option) { result |= optionKey }
        if modifierFlags.contains(.shift) { result |= shiftKey }
        if modifierFlags.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    private static let supportedModifiers: NSEvent.ModifierFlags = [
        .command,
        .shift,
        .option,
        .control
    ]

    private static let specialKeyLabels: [UInt16: String] = [
        UInt16(kVK_Space): "Space",
        UInt16(kVK_Return): "Return",
        UInt16(kVK_Tab): "Tab",
        UInt16(kVK_Delete): "Delete",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "Home",
        UInt16(kVK_End): "End",
        UInt16(kVK_PageUp): "Page Up",
        UInt16(kVK_PageDown): "Page Down",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12"
    ]
}

final class GlobalHotKeyController {
    private static let signature: OSType = 0x44534848 // "DSHH"

    private var hotKeyReference: EventHotKeyRef?
    private var eventHandlerReference: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    @discardableResult
    func register(
        shortcut: ShelfActivationShortcut,
        identifier: UInt32,
        action: @escaping @MainActor () -> Void
    ) -> Bool {
        invalidate()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerReference
        )
        guard installStatus == noErr else {
            NSLog("DropShelf could not install a global hotkey handler: %d", installStatus)
            invalidate()
            return false
        }

        let hotKeyID = EventHotKeyID(
            signature: Self.signature,
            id: identifier
        )
        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifierFlags,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyReference
        )
        guard registrationStatus == noErr else {
            NSLog(
                "DropShelf could not register global hotkey %@: %d",
                shortcut.displayName,
                registrationStatus
            )
            invalidate()
            return false
        }

        return true
    }

    @discardableResult
    func registerCommandShiftH(action: @escaping @MainActor () -> Void) -> Bool {
        register(
            shortcut: .historyShortcut,
            identifier: 1,
            action: action
        )
    }

    func invalidate() {
        if let hotKeyReference {
            UnregisterEventHotKey(hotKeyReference)
            self.hotKeyReference = nil
        }
        if let eventHandlerReference {
            RemoveEventHandler(eventHandlerReference)
            self.eventHandlerReference = nil
        }
        action = nil
    }

    private func performAction() {
        guard let action else { return }
        Task { @MainActor in
            action()
        }
    }

    private static let eventHandler: EventHandlerUPP = { _, _, userData in
        guard let userData else { return OSStatus(eventNotHandledErr) }
        let controller = Unmanaged<GlobalHotKeyController>
            .fromOpaque(userData)
            .takeUnretainedValue()
        controller.performAction()
        return noErr
    }
}
