import Testing
import Foundation
@testable import SlayoutCore

@Suite("LastLayoutSelector")
struct LastLayoutSelectorTests {
    let builtin = ScreenInfo(displayID: 1, name: "B",
                             frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                             visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
                             isBuiltin: true)
    let external = ScreenInfo(displayID: 2, name: "E",
                              frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
                              visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415),
                              isBuiltin: false)

    func snap(_ screens: [ScreenInfo], at t: Date = .distantPast, windowAt frame: CGRect = .zero) -> LayoutSnapshot {
        let win = WindowRef(id: 1, bundleID: "x", appName: "X", title: "T", frame: frame, screenID: screens[0].displayID)
        return LayoutCapture.capture(windows: [win], screens: screens, now: t)
    }

    final class TestClock {
        var t: Date = Date(timeIntervalSince1970: 0)
        func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
        var read: () -> Date { { self.t } }
    }

    @Test func firstTickDoesNotStabilize() {
        let clock = TestClock()
        let sel = LastLayoutSelector(stableInterval: 5, clock: clock.read)
        sel.tick(snap([builtin]))
        #expect(sel.stableByFingerprint.isEmpty)
    }

    @Test func sameFingerprintAfterIntervalStabilizes() {
        let clock = TestClock()
        let sel = LastLayoutSelector(stableInterval: 5, clock: clock.read)
        sel.tick(snap([builtin]))
        clock.advance(6)
        sel.tick(snap([builtin], windowAt: CGRect(x: 10, y: 20, width: 100, height: 100)))
        #expect(sel.snapshot(for: [builtin])?.windows.first?.frame == CGRect(x: 10, y: 20, width: 100, height: 100))
    }

    @Test func differentFingerprintResetsPending() {
        let clock = TestClock()
        let sel = LastLayoutSelector(stableInterval: 5, clock: clock.read)
        sel.tick(snap([builtin]))
        clock.advance(3)
        sel.tick(snap([builtin, external]))   // different fingerprint
        clock.advance(3)                       // still under stable interval since change
        sel.tick(snap([builtin, external]))
        #expect(sel.snapshot(for: [builtin, external]) == nil)
    }

    @Test func separateFingerprintsAreStoredIndependently() {
        let clock = TestClock()
        let sel = LastLayoutSelector(stableInterval: 5, clock: clock.read)
        // Fingerprint A
        sel.tick(snap([builtin]))
        clock.advance(10)
        sel.tick(snap([builtin]))
        // Fingerprint B
        clock.advance(1)
        sel.tick(snap([builtin, external]))
        clock.advance(10)
        sel.tick(snap([builtin, external]))
        #expect(sel.snapshot(for: [builtin]) != nil)
        #expect(sel.snapshot(for: [builtin, external]) != nil)
    }

    @Test func unknownScreenConfigYieldsNil() {
        let clock = TestClock()
        let sel = LastLayoutSelector(stableInterval: 5, clock: clock.read)
        sel.tick(snap([builtin]))
        clock.advance(10)
        sel.tick(snap([builtin]))
        #expect(sel.snapshot(for: [external]) == nil)
    }
}
