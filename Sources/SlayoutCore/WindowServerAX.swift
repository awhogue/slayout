import AppKit
import ApplicationServices

/// Real `WindowServer` backed by AXUIElement. Operates in top-left global
/// coordinates (which is what AX uses natively).
public final class WindowServerAX: WindowServer {
    private let screens: ScreenProvider

    public init(screens: ScreenProvider) {
        self.screens = screens
    }

    public func frontmostWindow() -> WindowRef? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        guard let window = copyAttribute(appEl, kAXFocusedWindowAttribute) else { return nil }
        let axWindow = window as! AXUIElement
        guard let frame = readFrame(axWindow) else { return nil }
        let title = (copyAttribute(axWindow, kAXTitleAttribute) as? String) ?? ""
        let bundleID = app.bundleIdentifier ?? ""
        let appName = app.localizedName ?? ""
        let screenID = screens.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) })?.displayID
            ?? screens.screens.first?.displayID ?? 0
        // CGWindowID is unavailable directly via AX; use the AXUIElement identity hash for now.
        let id = UInt32(truncatingIfNeeded: ObjectIdentifier(axWindow as AnyObject).hashValue)
        return WindowRef(id: id, bundleID: bundleID, appName: appName, title: title, frame: frame, screenID: screenID)
    }

    public func allWindows() -> [WindowRef] {
        // v1 stub: only the frontmost. allWindows() is fully implemented in step 7
        // (LayoutStore) using CGWindowListCopyWindowInfo to enumerate across apps.
        if let f = frontmostWindow() { return [f] }
        return []
    }

    public func setFrame(_ frame: CGRect, of window: WindowRef) {
        // Re-resolve the AX window for the frontmost app. v1: assume `window` is the frontmost.
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(appEl, kAXFocusedWindowAttribute) else { return }
        let axWindow = focused as! AXUIElement
        var pos = CGPoint(x: frame.minX, y: frame.minY)
        var size = CGSize(width: frame.width, height: frame.height)
        if let posVal = AXValueCreate(.cgPoint, &pos) {
            AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
    }

    public func focus(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            app.activate()
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // MARK: - Helpers

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return err == .success ? value : nil
    }

    private func readFrame(_ axWindow: AXUIElement) -> CGRect? {
        guard let posVal = copyAttribute(axWindow, kAXPositionAttribute),
              let sizeVal = copyAttribute(axWindow, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posVal as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }
}
