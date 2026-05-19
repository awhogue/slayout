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
        guard let app = NSWorkspace.shared.frontmostApplication else {
            SlayoutLog.vlog("frontmostWindow: NSWorkspace.frontmostApplication is nil")
            return nil
        }
        let appEl = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appEl, kAXFocusedWindowAttribute as CFString, &value)
        guard err == .success, let focused = value else {
            SlayoutLog.vlog("frontmostWindow: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?")) — AXFocusedWindow error=\(err.rawValue) (\(axErrorName(err)))")
            return nil
        }
        let axWindow = focused as! AXUIElement
        let ref = makeRef(for: axWindow,
                          bundleID: app.bundleIdentifier ?? "",
                          appName: app.localizedName ?? "")
        if ref == nil {
            SlayoutLog.vlog("frontmostWindow: \(app.localizedName ?? "?") — focused window has unreadable frame")
        }
        return ref
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
        var posErr: AXError = .success
        var sizeErr: AXError = .success
        if let posVal = AXValueCreate(.cgPoint, &pos) {
            posErr = AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, posVal)
        }
        if let sizeVal = AXValueCreate(.cgSize, &size) {
            sizeErr = AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeVal)
        }
        if posErr != .success || sizeErr != .success {
            SlayoutLog.log("Slayout: setFrame: \(window.appName) \"\(window.title)\" -> \(frame) posErr=\(axErrorName(posErr)) sizeErr=\(axErrorName(sizeErr))")
        } else {
            SlayoutLog.vlog("setFrame ok: \(window.appName) \"\(window.title)\" -> \(frame)")
        }
    }

    public func focus(bundleID: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            let ok = app.activate(options: [.activateAllWindows])
            SlayoutLog.vlog("focus: activate \(bundleID) -> \(ok)")
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            SlayoutLog.log("Slayout: focus: no app found for bundleID=\(bundleID)")
            return
        }
        SlayoutLog.vlog("focus: launching \(bundleID) at \(url.path)")
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

    private func axErrorName(_ err: AXError) -> String {
        switch err {
        case .success: return "success"
        case .failure: return "failure"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .invalidUIElementObserver: return "invalidUIElementObserver"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .actionUnsupported: return "actionUnsupported"
        case .notificationUnsupported: return "notificationUnsupported"
        case .notImplemented: return "notImplemented"
        case .notificationAlreadyRegistered: return "notificationAlreadyRegistered"
        case .notificationNotRegistered: return "notificationNotRegistered"
        case .apiDisabled: return "apiDisabled"
        case .noValue: return "noValue"
        case .parameterizedAttributeUnsupported: return "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: return "notEnoughPrecision"
        @unknown default: return "unknown(\(err.rawValue))"
        }
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
