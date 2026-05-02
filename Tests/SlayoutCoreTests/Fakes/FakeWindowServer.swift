import Foundation
@testable import SlayoutCore

final class FakeWindowServer: WindowServer {
    var windows: [WindowRef]
    var setFrameCalls: [(id: UInt32, frame: CGRect)] = []
    var focusCalls: [String] = []
    var frontmostID: UInt32?

    init(windows: [WindowRef] = [], frontmostID: UInt32? = nil) {
        self.windows = windows
        self.frontmostID = frontmostID ?? windows.first?.id
    }

    func frontmostWindow() -> WindowRef? {
        guard let id = frontmostID else { return nil }
        return windows.first(where: { $0.id == id })
    }

    func allWindows() -> [WindowRef] { windows }

    func setFrame(_ frame: CGRect, of window: WindowRef) {
        setFrameCalls.append((window.id, frame))
        if let idx = windows.firstIndex(where: { $0.id == window.id }) {
            windows[idx] = WindowRef(
                id: windows[idx].id,
                bundleID: windows[idx].bundleID,
                appName: windows[idx].appName,
                title: windows[idx].title,
                frame: frame,
                screenID: windows[idx].screenID
            )
        }
    }

    func focus(bundleID: String) {
        focusCalls.append(bundleID)
    }
}
