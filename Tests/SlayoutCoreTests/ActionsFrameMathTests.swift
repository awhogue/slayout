import Testing
import Foundation
@testable import SlayoutCore

@Suite("Actions frame math")
struct ActionsFrameMathTests {
    let vf = CGRect(x: 0, y: 0, width: 1200, height: 900)
    let cur = CGRect(x: 100, y: 100, width: 400, height: 300)

    @Test func fullscreen() {
        #expect(Actions.tile(.fullscreen, visibleFrame: vf, currentFrame: cur) == vf)
    }

    @Test func leftHalf() {
        #expect(Actions.tile(.leftHalf, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 0, y: 0, width: 600, height: 900))
    }

    @Test func rightHalf() {
        #expect(Actions.tile(.rightHalf, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 600, y: 0, width: 600, height: 900))
    }

    @Test func topHalf() {
        // Cocoa coords (origin bottom-left): "top" = upper, higher y.
        #expect(Actions.tile(.topHalf, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 0, y: 450, width: 1200, height: 450))
    }

    @Test func bottomHalf() {
        #expect(Actions.tile(.bottomHalf, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 0, y: 0, width: 1200, height: 450))
    }

    @Test func leftTwoThirds() {
        #expect(Actions.tile(.leftTwoThirds, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 0, y: 0, width: 800, height: 900))
    }

    @Test func rightTwoThirds() {
        #expect(Actions.tile(.rightTwoThirds, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 400, y: 0, width: 800, height: 900))
    }

    @Test func thirds() {
        #expect(Actions.tile(.leftThird, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 0, y: 0, width: 400, height: 900))
        #expect(Actions.tile(.middleThird, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 400, y: 0, width: 400, height: 900))
        #expect(Actions.tile(.rightThird, visibleFrame: vf, currentFrame: cur)
                == CGRect(x: 800, y: 0, width: 400, height: 900))
    }

    @Test func centerPreservesSize() {
        let r = Actions.tile(.center, visibleFrame: vf, currentFrame: cur)!
        #expect(r.size == cur.size)
        #expect(r.midX == vf.midX)
        #expect(r.midY == vf.midY)
    }

    @Test func screenActionIsNotATile() {
        #expect(Actions.tile(.screen("external"), visibleFrame: vf, currentFrame: cur) == nil)
    }

    @Test func tileWithOffsetVisibleFrameRespectsOrigin() {
        // visibleFrame on a secondary display offset to the right.
        let secondary = CGRect(x: 1200, y: 0, width: 1000, height: 800)
        #expect(Actions.tile(.leftHalf, visibleFrame: secondary, currentFrame: cur)
                == CGRect(x: 1200, y: 0, width: 500, height: 800))
    }
}

@Suite("Screen resolution")
struct ScreenResolutionTests {
    let builtin = ScreenInfo(
        displayID: 1, name: "Built-in",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        isBuiltin: true
    )
    let external = ScreenInfo(
        displayID: 2, name: "DELL U2723",
        frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415),
        isBuiltin: false
    )

    @Test func resolveBuiltin() {
        let r = Actions.resolveScreen("builtin", screens: [builtin, external], currentScreenID: 2)
        #expect(r?.displayID == 1)
    }

    @Test func resolveExternalReturnsFirstNonBuiltin() {
        let r = Actions.resolveScreen("external", screens: [builtin, external], currentScreenID: 1)
        #expect(r?.displayID == 2)
    }

    @Test func resolveByIndex() {
        let r = Actions.resolveScreen("0", screens: [builtin, external], currentScreenID: 1)
        #expect(r?.displayID == 1)
        let r2 = Actions.resolveScreen("1", screens: [builtin, external], currentScreenID: 1)
        #expect(r2?.displayID == 2)
    }

    @Test func resolveByName() {
        let r = Actions.resolveScreen("DELL U2723", screens: [builtin, external], currentScreenID: 1)
        #expect(r?.displayID == 2)
    }

    @Test func resolveUnknown() {
        let r = Actions.resolveScreen("nope", screens: [builtin, external], currentScreenID: 1)
        #expect(r == nil)
    }

    @Test func moveToScreenScalesPositionAndSize() {
        // Window covers half the width / full height of the source screen.
        let cur = CGRect(x: 0, y: 0, width: 720, height: 875)
        let mapped = Actions.moveToScreen(external, from: builtin, currentFrame: cur)
        // Should land on external screen, scaled proportionally to its visibleFrame.
        #expect(mapped.minX == external.visibleFrame.minX)
        #expect(mapped.minY == external.visibleFrame.minY)
        #expect(abs(mapped.width - external.visibleFrame.width / 2) < 1.0)
        #expect(abs(mapped.height - external.visibleFrame.height) < 1.0)
    }
}
