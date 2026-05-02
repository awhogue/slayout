import Testing
import Foundation
@testable import SlayoutCore

@Suite("Actions.apply end-to-end")
struct ActionsApplyTests {
    let builtin = ScreenInfo(
        displayID: 1, name: "Built-in",
        frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
        visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 875),
        isBuiltin: true
    )
    let external = ScreenInfo(
        displayID: 2, name: "DELL",
        frame: CGRect(x: 1440, y: 0, width: 2560, height: 1440),
        visibleFrame: CGRect(x: 1440, y: 0, width: 2560, height: 1415),
        isBuiltin: false
    )

    func makeWindow(screen: UInt32 = 1, frame: CGRect = CGRect(x: 100, y: 100, width: 600, height: 400)) -> WindowRef {
        WindowRef(id: 42, bundleID: "com.apple.Safari", appName: "Safari", title: "Apple", frame: frame, screenID: screen)
    }

    @Test func tileLeftHalfSetsExpectedFrame() throws {
        let win = makeWindow()
        let server = FakeWindowServer(windows: [win])
        try Actions.apply(.leftHalf, to: win, server: server, screens: [builtin, external])
        #expect(server.setFrameCalls.count == 1)
        #expect(server.setFrameCalls[0].id == 42)
        #expect(server.setFrameCalls[0].frame == CGRect(x: 0, y: 0, width: 720, height: 875))
    }

    @Test func screenExternalMovesWindowToOtherDisplay() throws {
        let win = makeWindow()
        let server = FakeWindowServer(windows: [win])
        try Actions.apply(.screen("external"), to: win, server: server, screens: [builtin, external])
        let f = server.setFrameCalls[0].frame
        #expect(f.minX >= external.visibleFrame.minX)
        #expect(f.minX < external.visibleFrame.maxX)
    }

    @Test func unknownScreenThrows() {
        let win = makeWindow()
        let server = FakeWindowServer(windows: [win])
        #expect(throws: ActionError.self) {
            try Actions.apply(.screen("nonexistent"), to: win, server: server, screens: [builtin, external])
        }
    }

    @Test func windowOnUnknownScreenThrows() {
        let win = makeWindow(screen: 99)
        let server = FakeWindowServer(windows: [win])
        #expect(throws: ActionError.self) {
            try Actions.apply(.leftHalf, to: win, server: server, screens: [builtin, external])
        }
    }
}
