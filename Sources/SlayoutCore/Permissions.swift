import AppKit
import ApplicationServices

public enum Permissions {
    @discardableResult
    public static func requestAccessibilityIfNeeded() -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

    public static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    public static func hasInputMonitoring() -> Bool {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    /// Triggers the Input Monitoring permission prompt and registers Slayout
    /// in the Input Monitoring list (so the user doesn't have to add it
    /// manually via the `+` button). Synchronous; returns `true` if granted.
    @discardableResult
    public static func requestInputMonitoringIfNeeded() -> Bool {
        if hasInputMonitoring() { return true }
        return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
    }

    public static func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
