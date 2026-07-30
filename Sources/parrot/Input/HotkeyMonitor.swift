import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Watches a configurable global shortcut and emits press/release edges.
/// Requires Accessibility permission. If the tap fails to register, callers
/// will see an error from `start()`.
final class HotkeyMonitor {
    enum Event: Equatable { case pressed, released }
    enum HotkeyError: Error { case tapCreateFailed }

    private var shortcut: HotkeyShortcut
    private var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false

    init(shortcut: HotkeyShortcut = .functionKey) {
        self.shortcut = shortcut
    }

    func start(onEvent: @escaping (Event) -> Void) throws {
        self.onEvent = onEvent

        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        if !trusted {
            throw HotkeyError.tapCreateFailed
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        // .cgSessionEventTap is the right level for an accessibility-granted
        // user process (.cghidEventTap requires root).
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: hotkeyCallback,
                userInfo: userInfo
            )
        else {
            throw HotkeyError.tapCreateFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    /// Apply a new shortcut without restarting the event tap. If the previous
    /// shortcut was held, emit its release edge first so recording cannot get
    /// stuck when a setting changes.
    func updateShortcut(_ shortcut: HotkeyShortcut) {
        if isPressed {
            isPressed = false
            emit(.released)
        }
        self.shortcut = shortcut
    }

    func setEnabled(_ enabled: Bool) {
        if !enabled, isPressed {
            isPressed = false
            emit(.released)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        onEvent = nil
    }

    /// Returns true when the event belongs to the configured shortcut and
    /// should be consumed instead of forwarded to the active application.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if shortcut.isModifierOnly {
            guard type == .flagsChanged else { return false }
            let pressed = shortcut.containsModifiers(event.flags)
            guard pressed != isPressed else { return pressed }
            isPressed = pressed
            emit(pressed ? .pressed : .released)
            return true
        }

        guard let configuredKeyCode = shortcut.keyCode else { return false }
        let eventKeyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard eventKeyCode == configuredKeyCode else { return false }

        switch type {
        case .keyDown:
            guard shortcut.matchesModifiers(event.flags) else { return false }
            if !isPressed {
                isPressed = true
                emit(.pressed)
            }
            return true
        case .keyUp:
            guard isPressed else { return false }
            isPressed = false
            emit(.released)
            return true
        default:
            return false
        }
    }

    fileprivate func reenableTap() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    private func emit(_ event: Event) {
        let handler = onEvent
        DispatchQueue.main.async {
            handler?(event)
        }
    }
}

private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        monitor.reenableTap()
        return Unmanaged.passUnretained(event)
    }

    if monitor.handle(type: type, event: event) {
        return nil
    }
    return Unmanaged.passUnretained(event)
}
