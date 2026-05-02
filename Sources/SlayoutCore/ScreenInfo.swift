import Foundation

public struct ScreenInfo: Equatable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isBuiltin: Bool

    public init(displayID: UInt32, name: String, frame: CGRect, visibleFrame: CGRect, isBuiltin: Bool) {
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isBuiltin = isBuiltin
    }
}

public protocol ScreenProvider {
    var screens: [ScreenInfo] { get }
}
