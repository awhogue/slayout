import Foundation

public struct WindowRef: Equatable, Sendable {
    public let id: UInt32
    public let bundleID: String
    public let appName: String
    public let title: String
    public let frame: CGRect
    public let screenID: UInt32

    public init(id: UInt32, bundleID: String, appName: String, title: String, frame: CGRect, screenID: UInt32) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.frame = frame
        self.screenID = screenID
    }
}

public protocol WindowServer {
    func frontmostWindow() -> WindowRef?
    func allWindows() -> [WindowRef]
    func setFrame(_ frame: CGRect, of window: WindowRef)
    func focus(bundleID: String)
}

public enum ActionError: Error, Equatable {
    case unknownScreen(String)
    case windowScreenNotFound(UInt32)
}
