import Testing
import Foundation
@testable import SlayoutCore

@Suite("LayoutCapture / LayoutRestore")
struct LayoutStoreTests {
    let builtin = ScreenInfo(displayID: 1, name: "Built-in",
                             frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                             visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
                             isBuiltin: true)
    let external = ScreenInfo(displayID: 2, name: "DELL",
                              frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
                              visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415),
                              isBuiltin: false)

    @Test func captureRecordsScreenIndexAndFrame() {
        let win = WindowRef(id: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple",
                            frame: CGRect(x: 100, y: 50, width: 600, height: 400), screenID: 1)
        let snap = LayoutCapture.capture(windows: [win], screens: [builtin, external], now: .distantPast)
        #expect(snap.windows.count == 1)
        #expect(snap.windows[0].screenIndex == 0)
        #expect(snap.windows[0].frame == win.frame)
        #expect(snap.screens.count == 2)
    }

    @Test func restoreExactTitleMatchWins() {
        let original = WindowRef(id: 1, bundleID: "com.google.Chrome", appName: "Chrome",
                                 title: "Apple - Google",
                                 frame: CGRect(x: 0, y: 0, width: 720, height: 875), screenID: 1)
        let snap = LayoutCapture.capture(windows: [original], screens: [builtin], now: .distantPast)
        let live = WindowRef(id: 999, bundleID: "com.google.Chrome", appName: "Chrome",
                             title: "Apple - Google",
                             frame: CGRect(x: 1000, y: 100, width: 200, height: 200), screenID: 1)
        let plan = LayoutRestore.plan(snapshot: snap, current: [live], screens: [builtin])
        #expect(plan.count == 1)
        #expect(plan[0].window.id == 999)
        #expect(plan[0].frame == original.frame)
    }

    @Test func restorePrefixMatchWhenTitleChanged() {
        let original = WindowRef(id: 1, bundleID: "com.google.Chrome", appName: "Chrome",
                                 title: "Apple - Google",
                                 frame: CGRect(x: 0, y: 0, width: 720, height: 800), screenID: 1)
        let snap = LayoutCapture.capture(windows: [original], screens: [builtin], now: .distantPast)
        let live = WindowRef(id: 999, bundleID: "com.google.Chrome", appName: "Chrome",
                             title: "Apple - Google Search Results",  // longer, but starts with the same prefix words
                             frame: CGRect(x: 1000, y: 100, width: 200, height: 200), screenID: 1)
        let plan = LayoutRestore.plan(snapshot: snap, current: [live], screens: [builtin])
        #expect(plan.count == 1)
        #expect(plan[0].window.id == 999)
    }

    @Test func restoreFirstWindowFallbackWhenNoTitleMatch() {
        let original = WindowRef(id: 1, bundleID: "com.apple.Terminal", appName: "Terminal",
                                 title: "ahogue@host: ~/code",
                                 frame: CGRect(x: 100, y: 100, width: 800, height: 600), screenID: 1)
        let snap = LayoutCapture.capture(windows: [original], screens: [builtin], now: .distantPast)
        let live = WindowRef(id: 999, bundleID: "com.apple.Terminal", appName: "Terminal",
                             title: "Completely Different",
                             frame: CGRect(x: 0, y: 0, width: 100, height: 100), screenID: 1)
        let plan = LayoutRestore.plan(snapshot: snap, current: [live], screens: [builtin])
        #expect(plan.count == 1)
        #expect(plan[0].window.id == 999)
    }

    @Test func claimedWindowsArentReused() {
        let snapWin1 = WindowRef(id: 1, bundleID: "com.google.Chrome", appName: "Chrome", title: "Apple",
                                 frame: CGRect(x: 0, y: 0, width: 100, height: 100), screenID: 1)
        let snapWin2 = WindowRef(id: 2, bundleID: "com.google.Chrome", appName: "Chrome", title: "Banana",
                                 frame: CGRect(x: 200, y: 200, width: 100, height: 100), screenID: 1)
        let snap = LayoutCapture.capture(windows: [snapWin1, snapWin2], screens: [builtin], now: .distantPast)
        // Live: only one Chrome window, with title "Apple". The second snapshot entry
        // should NOT also bind to it.
        let live = WindowRef(id: 999, bundleID: "com.google.Chrome", appName: "Chrome", title: "Apple",
                             frame: CGRect(x: 0, y: 0, width: 100, height: 100), screenID: 1)
        let plan = LayoutRestore.plan(snapshot: snap, current: [live], screens: [builtin])
        #expect(plan.count == 1)
        #expect(plan[0].window.id == 999)
    }

    @Test func appNotRunningIsSkipped() {
        let snapWin = WindowRef(id: 1, bundleID: "com.example.Missing", appName: "Missing", title: "X",
                                frame: CGRect(x: 0, y: 0, width: 100, height: 100), screenID: 1)
        let snap = LayoutCapture.capture(windows: [snapWin], screens: [builtin], now: .distantPast)
        let plan = LayoutRestore.plan(snapshot: snap, current: [], screens: [builtin])
        #expect(plan.isEmpty)
    }

    @Test func screenFingerprintMatchesByDisplayIDFirst() {
        let original = WindowRef(id: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "T",
                                 frame: CGRect(x: 1500, y: 100, width: 800, height: 600), screenID: 2)
        let snap = LayoutCapture.capture(windows: [original], screens: [builtin, external], now: .distantPast)
        // Live: same displayIDs, in the same order — restore exactly.
        let live = WindowRef(id: 999, bundleID: "com.apple.Safari", appName: "Safari", title: "T",
                             frame: .zero, screenID: 2)
        let plan = LayoutRestore.plan(snapshot: snap, current: [live], screens: [builtin, external])
        #expect(plan[0].frame == original.frame)
    }

    @Test func screenFingerprintFallsBackToIndexWhenIDChanged() {
        let original = WindowRef(id: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "T",
                                 frame: CGRect(x: 1500, y: 100, width: 800, height: 600), screenID: 2)
        let snap = LayoutCapture.capture(windows: [original], screens: [builtin, external], now: .distantPast)
        // Live: external display has different displayID (3 instead of 2) but same index/visibleFrame.
        let liveExternal = ScreenInfo(displayID: 3, name: "DELL",
                                      frame: external.frame,
                                      visibleFrame: external.visibleFrame,
                                      isBuiltin: false)
        let live = WindowRef(id: 999, bundleID: "com.apple.Safari", appName: "Safari", title: "T",
                             frame: .zero, screenID: 3)
        let plan = LayoutRestore.plan(snapshot: snap, current: [live], screens: [builtin, liveExternal])
        #expect(plan[0].frame == original.frame)
    }

    @Test func snapshotRoundTripsThroughJSON() throws {
        let win = WindowRef(id: 1, bundleID: "x", appName: "X", title: "T",
                            frame: CGRect(x: 0, y: 0, width: 10, height: 10), screenID: 1)
        let snap = LayoutCapture.capture(windows: [win], screens: [builtin], now: Date(timeIntervalSince1970: 1700000000))
        let data = try LayoutStore.encode(snap)
        let decoded = try LayoutStore.decode(data)
        #expect(decoded == snap)
    }
}
