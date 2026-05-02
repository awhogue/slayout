import Testing
@testable import SlayoutCore

@Suite("Bindings.handle dispatch")
struct BindingsDispatchTests {
    func makeConfig() -> Config {
        var cfg = Config()
        cfg.apps = ["t": "Terminal", "c": "Google Chrome"]
        cfg.windows = ["[": .leftTwoThirds, "return": .fullscreen, "up": .screen("external")]
        cfg.meta = MetaBindings(record: "s", restoreLast: "z", reload: "r")
        return cfg
    }

    @Test func hyperDownArmsButProducesNoEffect() {
        let b = Bindings(config: makeConfig())
        let r = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        #expect(r.consume == true)
        #expect(r.effect == .none)
    }

    @Test func hyperUpDisarms() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyUp, key: "f18", isHyperTrigger: true))
        #expect(r.consume == true)
        #expect(r.effect == .none)
    }

    @Test func keyWithoutHyperPassesThrough() {
        let b = Bindings(config: makeConfig())
        let r = b.handle(KeyEvent(kind: .keyDown, key: "t", isHyperTrigger: false))
        #expect(r.consume == false)
        #expect(r.effect == .none)
    }

    @Test func appBindingFires() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "t", isHyperTrigger: false))
        #expect(r.consume == true)
        #expect(r.effect == .focusApp("Terminal"))
    }

    @Test func windowBindingFires() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "[", isHyperTrigger: false))
        #expect(r.effect == .windowAction(.leftTwoThirds))
    }

    @Test func screenBindingFires() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "up", isHyperTrigger: false))
        #expect(r.effect == .windowAction(.screen("external")))
    }

    @Test func metaRecordFires() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "s", isHyperTrigger: false))
        #expect(r.effect == .enterRecord)
    }

    @Test func metaRestoreLastFires() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "z", isHyperTrigger: false))
        #expect(r.effect == .restoreLast)
    }

    @Test func metaReloadFires() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "r", isHyperTrigger: false))
        #expect(r.effect == .reload)
    }

    @Test func unboundHyperKeyIsConsumedButNoEffect() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "x", isHyperTrigger: false))
        #expect(r.consume == true)
        #expect(r.effect == .none)
    }

    @Test func bindingPriorityWindowOverApp() {
        // If both apps and windows have a key, window action wins (more specific use case).
        var cfg = makeConfig()
        cfg.apps["return"] = "Finder"
        let b = Bindings(config: cfg)
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        let r = b.handle(KeyEvent(kind: .keyDown, key: "return", isHyperTrigger: false))
        #expect(r.effect == .windowAction(.fullscreen))
    }

    @Test func keyUpUnderHyperPassesThrough() {
        let b = Bindings(config: makeConfig())
        _ = b.handle(KeyEvent(kind: .keyDown, key: "f18", isHyperTrigger: true))
        // Tests that keyUp events for non-trigger keys don't trigger an effect.
        let r = b.handle(KeyEvent(kind: .keyUp, key: "t", isHyperTrigger: false))
        #expect(r.consume == true)  // still swallowed while hyper is held
        #expect(r.effect == .none)
    }
}
