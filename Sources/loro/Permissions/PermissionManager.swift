import AppKit
import ApplicationServices
import AVFoundation
import Combine
import Foundation

@MainActor
final class PermissionManager: ObservableObject {
    @Published private(set) var microphoneStatus: AVAuthorizationStatus
    @Published private(set) var accessibilityGranted: Bool

    var onStatusChange: (() -> Void)?

    private var activeObserver: NSObjectProtocol?

    init() {
        microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        accessibilityGranted = AXIsProcessTrusted()

        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    deinit {
        if let activeObserver {
            NotificationCenter.default.removeObserver(activeObserver)
        }
    }

    var microphoneGranted: Bool {
        microphoneStatus == .authorized
    }

    var allRequiredPermissionsGranted: Bool {
        microphoneGranted && accessibilityGranted
    }

    func refresh() {
        let nextMicrophoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let nextAccessibilityGranted = AXIsProcessTrusted()
        let changed =
            nextMicrophoneStatus != microphoneStatus
            || nextAccessibilityGranted != accessibilityGranted

        microphoneStatus = nextMicrophoneStatus
        accessibilityGranted = nextAccessibilityGranted

        if changed {
            onStatusChange?()
        }
    }

    func requestMicrophone() {
        guard microphoneStatus == .notDetermined else {
            openMicrophoneSettings()
            return
        }

        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func openMicrophoneSettings() {
        openPrivacySettings(pane: "Privacy_Microphone")
    }

    func openAccessibilitySettings() {
        openPrivacySettings(pane: "Privacy_Accessibility")
    }

    private func openPrivacySettings(pane: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
