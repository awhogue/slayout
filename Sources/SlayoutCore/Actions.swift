import Foundation

public enum Actions {

    /// Compute the target frame for a tile-style action within the given visible frame.
    /// Returns nil for non-tile actions (e.g. `.screen(_)`).
    /// All SlayoutCore geometry uses **top-left global coordinates** (AX / CGWindowList style):
    /// y grows downward, primary display origin at (0, 0). NSScreenProvider converts NSScreen
    /// frames into this convention.
    public static func tile(_ action: WindowAction, visibleFrame vf: CGRect, currentFrame cur: CGRect) -> CGRect? {
        switch action {
        case .fullscreen:
            return vf
        case .leftHalf:
            return CGRect(x: vf.minX, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .rightHalf:
            return CGRect(x: vf.minX + vf.width / 2, y: vf.minY, width: vf.width / 2, height: vf.height)
        case .topHalf:
            return CGRect(x: vf.minX, y: vf.minY, width: vf.width, height: vf.height / 2)
        case .bottomHalf:
            return CGRect(x: vf.minX, y: vf.minY + vf.height / 2, width: vf.width, height: vf.height / 2)
        case .leftTwoThirds:
            return CGRect(x: vf.minX, y: vf.minY, width: vf.width * 2 / 3, height: vf.height)
        case .rightTwoThirds:
            return CGRect(x: vf.minX + vf.width / 3, y: vf.minY, width: vf.width * 2 / 3, height: vf.height)
        case .leftThird:
            return CGRect(x: vf.minX, y: vf.minY, width: vf.width / 3, height: vf.height)
        case .middleThird:
            return CGRect(x: vf.minX + vf.width / 3, y: vf.minY, width: vf.width / 3, height: vf.height)
        case .rightThird:
            return CGRect(x: vf.minX + vf.width * 2 / 3, y: vf.minY, width: vf.width / 3, height: vf.height)
        case .center:
            let w = min(cur.width, vf.width)
            let h = min(cur.height, vf.height)
            return CGRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
        case .screen:
            return nil
        }
    }

    /// Resolve a `screen:<name>` argument to a target ScreenInfo.
    /// Recognized names: "builtin", "external", a numeric index, or a screen `name` exact match.
    public static func resolveScreen(_ name: String,
                                     screens: [ScreenInfo],
                                     currentScreenID: UInt32) -> ScreenInfo? {
        let lower = name.lowercased()
        switch lower {
        case "builtin":
            return screens.first(where: { $0.isBuiltin })
        case "external":
            return screens.first(where: { !$0.isBuiltin })
        default:
            if let idx = Int(lower), screens.indices.contains(idx) {
                return screens[idx]
            }
            return screens.first(where: { $0.name == name })
        }
    }

    /// Apply a WindowAction to a window through a WindowServer.
    /// Resolves the target frame and target screen, then delegates to `server.setFrame`.
    public static func apply(_ action: WindowAction,
                             to window: WindowRef,
                             server: WindowServer,
                             screens: [ScreenInfo]) throws {
        guard let currentScreen = screens.first(where: { $0.displayID == window.screenID }) else {
            throw ActionError.windowScreenNotFound(window.screenID)
        }

        switch action {
        case .screen(let name):
            guard let target = resolveScreen(name, screens: screens, currentScreenID: window.screenID) else {
                throw ActionError.unknownScreen(name)
            }
            let newFrame = moveToScreen(target, from: currentScreen, currentFrame: window.frame)
            server.setFrame(newFrame, of: window)
        default:
            if let newFrame = tile(action, visibleFrame: currentScreen.visibleFrame, currentFrame: window.frame) {
                server.setFrame(newFrame, of: window)
            }
        }
    }

    /// Move a window to another screen, scaling its frame proportionally
    /// from the source screen's visibleFrame to the target's visibleFrame.
    public static func moveToScreen(_ target: ScreenInfo,
                                    from source: ScreenInfo,
                                    currentFrame cur: CGRect) -> CGRect {
        let svf = source.visibleFrame
        let tvf = target.visibleFrame
        guard svf.width > 0, svf.height > 0 else { return cur }
        let fx = (cur.minX - svf.minX) / svf.width
        let fy = (cur.minY - svf.minY) / svf.height
        let fw = cur.width / svf.width
        let fh = cur.height / svf.height
        return CGRect(
            x: tvf.minX + fx * tvf.width,
            y: tvf.minY + fy * tvf.height,
            width: fw * tvf.width,
            height: fh * tvf.height
        )
    }
}
