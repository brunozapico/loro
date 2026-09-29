import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import LoroCore

/// Watches a configurable global shortcut and emits press/release edges.
/// Requires Accessibility permission. If the tap fails to register, callers
/// will see an error from `start()`.
final class HotkeyMonitor {
    enum Event: Equatable { case pressed, released }
    enum HotkeyError: Error { case tapCreateFailed }

    private let stateLock = NSRecursiveLock()
    private var eventRunLoop: CFRunLoop?
    private var workerFinished: DispatchSemaphore?
    private var shortcut: HotkeyShortcut
    private var onEvent: ((Event) -> Void)?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isPressed = false
    private var enabled = true

    var isRunning: Bool { tap != nil }

    init(shortcut: HotkeyShortcut = .functionKey) {
        self.shortcut = shortcut
    }

    func start(onEvent: @escaping (Event) -> Void) throws {
        guard tap == nil else { return }
        self.onEvent = onEvent

        if !AXIsProcessTrusted() {
            throw HotkeyError.tapCreateFailed
        }

        // Audio-engine startup can block the main run loop long enough for
        // macOS to disable its event tap. Keep keyboard delivery independent.
        let ready = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        workerFinished = finished
        let thread = Thread { [self] in
            defer { finished.signal() }
            let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
            guard let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: hotkeyCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            ), let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                ready.signal()
                return
            }
            self.tap = tap
            self.runLoopSource = source
            self.eventRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(self.eventRunLoop, source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            ready.signal()
            CFRunLoopRun()
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFMachPortInvalidate(tap)
        }
        thread.name = "Loro shortcut monitor"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
        guard tap != nil else {
            finished.wait()
            workerFinished = nil
            throw HotkeyError.tapCreateFailed
        }
    }

    /// Apply a new shortcut without restarting the event tap. If the previous
    /// shortcut was held, emit its release edge first so recording cannot get
    /// stuck when a setting changes.
    func updateShortcut(_ shortcut: HotkeyShortcut) {
        stateLock.lock()
        defer { stateLock.unlock() }
        if isPressed {
            isPressed = false
            emit(.released)
        }
        self.shortcut = shortcut
    }

    func setEnabled(_ enabled: Bool) {
        stateLock.lock()
        defer { stateLock.unlock() }
        self.enabled = enabled
        if !enabled, isPressed {
            isPressed = false
            emit(.released)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: enabled)
        }
    }

    func stop() {
        stateLock.lock()
        enabled = false
        stateLock.unlock()
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let eventRunLoop {
            CFRunLoopPerformBlock(eventRunLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopStop(CFRunLoopGetCurrent())
            }
            CFRunLoopWakeUp(eventRunLoop)
            workerFinished?.wait()
        }
        stateLock.lock()
        defer { stateLock.unlock() }
        isPressed = false
        tap = nil
        runLoopSource = nil
        eventRunLoop = nil
        workerFinished = nil
        onEvent = nil
        enabled = true
    }

    /// Returns true when the event belongs to the configured shortcut and
    /// should be consumed instead of forwarded to the active application.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard enabled else { return false }
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
        stateLock.lock()
        defer { stateLock.unlock() }
        // A timeout is not a key release. Reconcile against physical state so
        // a held shortcut stays held, but a release missed during suspension
        // still stops capture. Never synthesize another press in Toggle mode.
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiersHeld = shortcut.containsModifiers(flags)
        let keyHeld = shortcut.keyCode.map {
            CGEventSource.keyState(.combinedSessionState, key: $0)
        } ?? true
        if HotkeyRecovery.shouldRelease(isPressed: isPressed,
                                        modifiersHeld: modifiersHeld, keyHeld: keyHeld) {
            isPressed = false
            emit(.released)
        }
        if enabled, let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    private func emit(_ event: Event) {
        DispatchQueue.main.async { [weak self] in
            self?.onEvent?(event)
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
