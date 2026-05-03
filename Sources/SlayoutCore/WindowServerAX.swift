import AppKit
import ApplicationServices
import CoreFoundation

/// Real `WindowServer` backed by AXUIElement. Operates in top-left global
/// coordinates (which is what AX uses natively).
///
/// Maintains an in-memory cache of `WindowRef.id` → `AXUIElement` populated
/// by `allWindows()` / `frontmostWindow()` so that `setFrame(_:of:)` can
/// target a specific window even when its app isn't frontmost.
public final class WindowServerAX: WindowServer {
    private let screens: ScreenProvider
    private var axCache: [UInt32: AXUIElement] = [:]

    public init(screens: ScreenProvider) {
        self.screens = screens
    }

    public func frontmostWindow() -> WindowRef? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        guard let focused = copyAttribute(appEl, kAXFocusedWindowAttribute) else { return nil }
        let axWindow = focused as! AXUIElement
        return makeRef(for: axWindow,
                       bundleID: app.bundleIdentifier ?? "",
                       appName: app.localizedName ?? "")
    }

    public func allWindows() -> [WindowRef] {
        var result: [WindowRef] = []
        axCache.removeAll(keepingCapacity: true)
        for app in NSWorkspace.shared.runningApplications {
            guard app.activationPolicy == .regular else { continue }
            guard let bundleID = app.bundleIdentifier else { continue }
            let appName = app.localizedName ?? bundleID
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            guard let raw = copyAttribute(appEl, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for axWindow in raw {
                if let ref = makeRef(for: axWindow, bundleID: bundleID, appName: appName) {
                    result.append(ref)
                }
            }
        }
        return result
    }

    public func setFrame(_ frame: CGRect, of window: WindowRef) {
        guard let axWindow = axCache[window.id] else {
            SlayoutLog.log("Slayout: setFrame: no AX handle cached for window id=\(window.id) (\(window.appName) \"\(window.title)\")")
            return
        }
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

    private func makeRef(for axWindow: AXUIElement, bundleID: String, appName: String) -> WindowRef? {
        guard let frame = readFrame(axWindow) else { return nil }
        let title = (copyAttribute(axWindow, kAXTitleAttribute) as? String) ?? ""
        let id = UInt32(truncatingIfNeeded: CFHash(axWindow))
        axCache[id] = axWindow
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screenID = screens.screens.first(where: { $0.frame.contains(center) })?.displayID
            ?? screens.screens.first?.displayID ?? 0
        return WindowRef(id: id, bundleID: bundleID, appName: appName, title: title, frame: frame, screenID: screenID)
    }

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
        // Ignore minimized / hidden windows whose AX frames are zero-sized.
        if size.width < 1 || size.height < 1 { return nil }
        return CGRect(origin: point, size: size)
    }
}
