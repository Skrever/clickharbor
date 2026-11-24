import AppKit
import Carbon.HIToolbox
import SwiftUI

enum MouseMacroInput {
    static let mouseButtons: [(UInt16, String)] = [
        (1, "Левая"), (2, "Правая"), (4, "Колесо"), (8, "Назад"), (16, "Вперёд"),
    ]
    static let modifiers: [(UInt16, String)] = [
        (1, "Левый Control"), (2, "Левый Shift"), (4, "Левый Option"), (8, "Левый Command"),
        (16, "Правый Control"), (32, "Правый Shift"), (64, "Правый Option"), (128, "Правый Command"),
    ]

    private static let letters = [
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
        kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
        kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
        kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
    ]
    private static let numbers = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0,
    ]
    private static let functions = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                                    kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
    private static let extras: [(Int, UInt16, String)] = [
        (kVK_Return, 40, "Return"), (kVK_Escape, 41, "Escape"), (kVK_Delete, 42, "Delete"),
        (kVK_Tab, 43, "Tab"), (kVK_Space, 44, "Пробел"), (kVK_ANSI_Minus, 45, "−"),
        (kVK_ANSI_Equal, 46, "="), (kVK_ANSI_LeftBracket, 47, "["), (kVK_ANSI_RightBracket, 48, "]"),
        (kVK_ANSI_Backslash, 49, "\\"), (kVK_ANSI_Semicolon, 51, ";"), (kVK_ANSI_Quote, 52, "’"),
        (kVK_ANSI_Grave, 53, "`"), (kVK_ANSI_Comma, 54, ","), (kVK_ANSI_Period, 55, "."),
        (kVK_ANSI_Slash, 56, "/"), (kVK_CapsLock, 57, "Caps Lock"), (kVK_Home, 74, "Home"),
        (kVK_PageUp, 75, "Page Up"), (kVK_ForwardDelete, 76, "Forward Delete"),
        (kVK_End, 77, "End"), (kVK_PageDown, 78, "Page Down"),
        (kVK_RightArrow, 79, "→"), (kVK_LeftArrow, 80, "←"), (kVK_DownArrow, 81, "↓"), (kVK_UpArrow, 82, "↑"),
        (kVK_ANSI_KeypadEnter, 88, "Enter (NumPad)"), (kVK_ISO_Section, 100, "§"),
    ]

    private static let keyTable: [(Int, UInt16, String)] = {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let digits = Array("1234567890")
        let letterKeys = letters.enumerated().map { ($0.element, UInt16($0.offset + 4), String(alphabet[$0.offset])) }
        let numberKeys = numbers.enumerated().map { ($0.element, UInt16($0.offset + 30), String(digits[$0.offset])) }
        let functionKeys = functions.enumerated().map { ($0.element, UInt16($0.offset + 58), "F\($0.offset + 1)") }
        return (letterKeys + numberKeys + functionKeys + extras).sorted { $0.1 < $1.1 }
    }()

    static let keys = keyTable.map { ($0.1, $0.2) }

    static func key(_ code: Int) -> UInt16? { keyTable.first { $0.0 == code }?.1 }

    static func modifier(_ code: Int) -> UInt16? {
        let virtualCodes = [kVK_Control, kVK_Shift, kVK_Option, kVK_Command,
                            kVK_RightControl, kVK_RightShift, kVK_RightOption, kVK_RightCommand]
        guard let index = virtualCodes.firstIndex(of: code) else { return nil }
        return modifiers[index].0
    }
}

struct MouseMacroRecorder: NSViewRepresentable {
    let event: (MouseMacroEvent, TimeInterval) -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.event = event
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) { view.event = event }

    final class CaptureView: NSView {
        var event: ((MouseMacroEvent, TimeInterval) -> Void)?
        private var modifiers: Set<UInt16> = []

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }

        override func keyDown(with event: NSEvent) {
            guard !event.isARepeat else { return }
            emitKey(event, pressed: true)
        }

        override func keyUp(with event: NSEvent) { emitKey(event, pressed: false) }

        override func flagsChanged(with event: NSEvent) {
            guard let value = MouseMacroInput.modifier(Int(event.keyCode)) else { return }
            let pressed = !modifiers.contains(value)
            if pressed { modifiers.insert(value) } else { modifiers.remove(value) }
            emit(.modifier, value: value, pressed: pressed, at: event.timestamp)
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            emitMouse(event, pressed: true)
        }
        override func mouseUp(with event: NSEvent) { emitMouse(event, pressed: false) }
        override func rightMouseDown(with event: NSEvent) { emitMouse(event, pressed: true) }
        override func rightMouseUp(with event: NSEvent) { emitMouse(event, pressed: false) }
        override func otherMouseDown(with event: NSEvent) { emitMouse(event, pressed: true) }
        override func otherMouseUp(with event: NSEvent) { emitMouse(event, pressed: false) }

        private func emitKey(_ event: NSEvent, pressed: Bool) {
            guard let value = MouseMacroInput.key(Int(event.keyCode)) else { return }
            emit(.key, value: value, pressed: pressed, at: event.timestamp)
        }

        private func emitMouse(_ event: NSEvent, pressed: Bool) {
            guard MouseMacroInput.mouseButtons.indices.contains(event.buttonNumber) else { return }
            emit(.mouse, value: MouseMacroInput.mouseButtons[event.buttonNumber].0,
                 pressed: pressed, at: event.timestamp)
        }

        private func emit(_ kind: MouseMacroEvent.Kind, value: UInt16, pressed: Bool, at time: TimeInterval) {
            event?(MouseMacroEvent(kind: kind, value: value, pressed: pressed, delayMs: 0), time)
        }
    }
}
