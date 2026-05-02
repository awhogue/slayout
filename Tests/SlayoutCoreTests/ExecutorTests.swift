import Testing
import Foundation
@testable import SlayoutCore

final class FakeScreenProvider: ScreenProvider {
    var _screens: [ScreenInfo]
    init(_ screens: [ScreenInfo]) { self._screens = screens }
    var screens: [ScreenInfo] { _screens }
}

@Suite("Executor")
struct ExecutorTests {
    let builtin = ScreenInfo(displayID: 1, name: "B", frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                             visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875), isBuiltin: true)
    let win = WindowRef(id: 1, bundleID: "com.apple.Safari", appName: "Safari", title: "T",
                        frame: CGRect(x: 0, y: 0, width: 100, height: 100), screenID: 1)

    @Test func windowActionInvokesSetFrame() {
        let server = FakeWindowServer(windows: [win])
        let screens = FakeScreenProvider([builtin])
        let exec = Executor(server: server, screens: screens)
        exec.run(.windowAction(.leftHalf))
        #expect(server.setFrameCalls.count == 1)
        #expect(server.setFrameCalls[0].frame == CGRect(x: 0, y: 0, width: 720, height: 875))
    }

    @Test func focusAppPrefersLookupOverRawName() {
        let server = FakeWindowServer(windows: [win])
        let screens = FakeScreenProvider([builtin])
        let exec = Executor(server: server, screens: screens, lookupBundleID: { name in
            name == "Terminal" ? "com.apple.Terminal" : nil
        })
        exec.run(.focusApp("Terminal"))
        #expect(server.focusCalls == ["com.apple.Terminal"])
    }

    @Test func focusAppFallsBackToRawName() {
        let server = FakeWindowServer(windows: [win])
        let screens = FakeScreenProvider([builtin])
        let exec = Executor(server: server, screens: screens)
        exec.run(.focusApp("com.apple.Terminal"))
        #expect(server.focusCalls == ["com.apple.Terminal"])
    }

    @Test func metaHooksFire() {
        let server = FakeWindowServer(windows: [win])
        let screens = FakeScreenProvider([builtin])
        var hooks = ExecutorHooks()
        var recordCalls = 0, restoreCalls = 0, reloadCalls = 0
        hooks.enterRecord = { recordCalls += 1 }
        hooks.restoreLast = { restoreCalls += 1 }
        hooks.reload = { reloadCalls += 1 }
        let exec = Executor(server: server, screens: screens, hooks: hooks)
        exec.run(.enterRecord)
        exec.run(.restoreLast)
        exec.run(.reload)
        #expect(recordCalls == 1)
        #expect(restoreCalls == 1)
        #expect(reloadCalls == 1)
    }
}
