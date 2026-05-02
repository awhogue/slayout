import Testing
import Foundation
@testable import SlayoutCore

@Suite("Recorder")
struct RecorderTests {
    func makeSnap() -> LayoutSnapshot {
        let s = ScreenInfo(displayID: 1, name: "B",
                           frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                           visibleFrame: CGRect(x: 0, y: 0, width: 1, height: 1), isBuiltin: true)
        return LayoutCapture.capture(windows: [], screens: [s], now: .distantPast)
    }

    @Test func bindNonReservedKeySaves() {
        var saved: [(String, LayoutSnapshot)] = []
        let snap = makeSnap()
        let r = Recorder(captureSnapshot: { snap },
                         saveLayout: { saved.append(($0, $1)) },
                         isReserved: { _ in false })
        let result = r.bind(to: "1")
        #expect(result == .bound(key: "1"))
        #expect(saved.count == 1)
        #expect(saved[0].0 == "1")
        #expect(saved[0].1 == snap)
    }

    @Test func bindReservedKeyAborts() {
        var saved: [(String, LayoutSnapshot)] = []
        let r = Recorder(captureSnapshot: { self.makeSnap() },
                         saveLayout: { saved.append(($0, $1)) },
                         isReserved: { $0 == "t" })
        let result = r.bind(to: "t")
        if case .aborted = result {} else { Issue.record("expected aborted, got \(result)") }
        #expect(saved.isEmpty)
    }
}

@Suite("Bindings recording mode")
struct BindingsRecordingModeTests {
    func cfg() -> Config {
        var c = Config()
        c.windows = ["[": .leftHalf]
        c.apps = ["t": "Terminal"]
        c.meta = MetaBindings(record: "s", restoreLast: "z", reload: "r")
        return c
    }

    @Test func recordKeyEntersRecordingMode() {
        let b = Bindings(config: cfg())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "s", isHyperTrigger: false))
        #expect(r.effect == .enterRecord)
        #expect(b.isRecording == true)
    }

    @Test func nextHyperKeyBindsLayout() {
        let b = Bindings(config: cfg())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        _ = b.handle(KeyEvent(kind: .keyDown, key: "s", isHyperTrigger: false))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "1", isHyperTrigger: false))
        #expect(r.effect == .bindLayout("1"))
        #expect(b.isRecording == false)
    }

    @Test func reRecordingKeyCancels() {
        let b = Bindings(config: cfg())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        _ = b.handle(KeyEvent(kind: .keyDown, key: "s", isHyperTrigger: false))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "s", isHyperTrigger: false))
        #expect(r.effect == .enterRecord)  // cancellation reuses enterRecord effect
        #expect(b.isRecording == false)
    }

    @Test func savedLayoutKeyDispatches() {
        let b = Bindings(config: cfg())
        b.savedLayouts = ["1"]
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "1", isHyperTrigger: false))
        #expect(r.effect == .restoreLayout("1"))
    }

    @Test func configBindingBeatsSavedLayout() {
        let b = Bindings(config: cfg())
        b.savedLayouts = ["["]
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "[", isHyperTrigger: false))
        #expect(r.effect == .windowAction(.leftHalf))
    }
}
