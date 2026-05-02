import AppKit
import CoreGraphics

/// Real `ScreenProvider` backed by `NSScreen.screens`, exposing geometry in
/// top-left global coordinates so it composes cleanly with AX / CGWindowList.
public final class NSScreenProvider: ScreenProvider {
    public init() {}

    public var screens: [ScreenInfo] {
        let nsScreens = NSScreen.screens
        // The "primary" screen (origin at 0,0 in Cocoa coords) defines the height
        // we use to flip from bottom-left to top-left.
        let primaryHeight = nsScreens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? nsScreens.first?.frame.height
            ?? 0
        return nsScreens.map { Self.makeInfo($0, primaryHeight: primaryHeight) }
    }

    private static func makeInfo(_ screen: NSScreen, primaryHeight: CGFloat) -> ScreenInfo {
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
        let name = screen.localizedName
        let isBuiltin = CGDisplayIsBuiltin(id) != 0
        return ScreenInfo(
            displayID: id,
            name: name,
            frame: flipToTopLeft(screen.frame, primaryHeight: primaryHeight),
            visibleFrame: flipToTopLeft(screen.visibleFrame, primaryHeight: primaryHeight),
            isBuiltin: isBuiltin
        )
    }

    /// Convert a Cocoa rect (origin bottom-left, primary at 0,0) to top-left global coords.
    static func flipToTopLeft(_ r: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }
}
