import Testing
@testable import SlayoutCore

@Suite("Config parsing")
struct ConfigTests {

    @Test("empty TOML yields defaults")
    func emptyDefaults() throws {
        let cfg = try ConfigLoader.parse("")
        #expect(cfg.hyperTrigger == .capsLock)
        #expect(cfg.apps.isEmpty)
        #expect(cfg.windows.isEmpty)
        #expect(cfg.meta == MetaBindings())
    }

    @Test("hyper trigger parses each variant")
    func hyperTriggerVariants() throws {
        let cases: [(String, HyperTrigger)] = [
            ("caps_lock", .capsLock),
            ("right_cmd", .rightCmd),
            ("right_option", .rightOption),
            ("f19", .f19),
        ]
        for (raw, expected) in cases {
            let cfg = try ConfigLoader.parse("[hyper]\ntrigger = \"\(raw)\"\n")
            #expect(cfg.hyperTrigger == expected, "for \(raw)")
        }
    }

    @Test("unknown hyper trigger throws")
    func unknownTriggerThrows() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("[hyper]\ntrigger = \"jiggle\"\n")
        }
    }

    @Test("apps section maps keys to app names")
    func appsSection() throws {
        let cfg = try ConfigLoader.parse("""
        [apps]
        T = "Terminal"
        C = "Google Chrome"
        """)
        #expect(cfg.apps["t"] == "Terminal")
        #expect(cfg.apps["c"] == "Google Chrome")
    }

    @Test("window section parses built-in actions")
    func windowActions() throws {
        let cfg = try ConfigLoader.parse("""
        [window]
        "return" = "fullscreen"
        "[" = "left-two-thirds"
        "]" = "right-two-thirds"
        "h" = "left-half"
        "l" = "right-half"
        "up" = "screen:external"
        "down" = "screen:builtin"
        "c" = "center"
        """)
        #expect(cfg.windows["return"] == .fullscreen)
        #expect(cfg.windows["["] == .leftTwoThirds)
        #expect(cfg.windows["]"] == .rightTwoThirds)
        #expect(cfg.windows["h"] == .leftHalf)
        #expect(cfg.windows["l"] == .rightHalf)
        #expect(cfg.windows["up"] == .screen("external"))
        #expect(cfg.windows["down"] == .screen("builtin"))
        #expect(cfg.windows["c"] == .center)
    }

    @Test("unknown window action throws")
    func unknownWindowAction() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("""
            [window]
            "x" = "do-the-funky-thing"
            """)
        }
    }

    @Test("meta bindings populate")
    func metaBindings() throws {
        let cfg = try ConfigLoader.parse("""
        [meta]
        record = "s"
        restore_last = "z"
        reload = "r"
        """)
        #expect(cfg.meta.record == "s")
        #expect(cfg.meta.restoreLast == "z")
        #expect(cfg.meta.reload == "r")
    }

    @Test("malformed TOML throws parseError")
    func malformedToml() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parse("[hyper\ntrigger = ")
        }
    }

    @Test("middle-two-thirds parses, '|' normalizes to '\\\\'")
    func middleTwoThirds() throws {
        let cfg = try ConfigLoader.parse("""
        [window]
        "|" = "middle-two-thirds"
        """)
        // Event tap reports the unshifted key '\', so the config entry must be
        // stored under '\' for binding lookup to succeed.
        #expect(cfg.windows["\\"] == .middleTwoThirds)
        #expect(cfg.windows["|"] == nil)
    }

    @Test("shifted-symbol keys normalize to unshifted form")
    func shiftedSymbolAliases() throws {
        let cfg = try ConfigLoader.parse("""
        [window]
        "?" = "fullscreen"
        ":" = "left-half"
        [apps]
        "!" = "Terminal"
        """)
        #expect(cfg.windows["/"] == .fullscreen)
        #expect(cfg.windows[";"] == .leftHalf)
        #expect(cfg.apps["1"] == "Terminal")
    }

    @Test("resilient parse skips bad entries and reports warnings")
    func resilientParseSkipsBad() throws {
        let result = try ConfigLoader.parseResilient("""
        [window]
        "h" = "left-half"
        "x" = "do-the-funky-thing"
        "|" = "middle-two-thirds"
        """)
        #expect(result.config.windows["h"] == .leftHalf)
        #expect(result.config.windows["\\"] == .middleTwoThirds)
        #expect(result.config.windows["x"] == nil)
        #expect(result.warnings.count == 1)
        #expect(result.warnings.first?.contains("window.x") == true)
    }

    @Test("resilient parse still throws on TOML syntax error")
    func resilientParseStructuralError() {
        #expect(throws: ConfigError.self) {
            try ConfigLoader.parseResilient("[hyper\ntrigger = ")
        }
    }

    @Test("resilient parse keeps default trigger when value is unknown")
    func resilientParseUnknownTrigger() throws {
        let result = try ConfigLoader.parseResilient("[hyper]\ntrigger = \"jiggle\"\n")
        #expect(result.config.hyperTrigger == .capsLock)
        #expect(result.warnings.contains(where: { $0.contains("jiggle") }))
    }

    @Test("uppercase key in apps is normalized to lowercase")
    func keyNormalization() throws {
        let cfg = try ConfigLoader.parse("""
        [apps]
        T = "Terminal"
        """)
        #expect(cfg.apps["t"] == "Terminal")
        #expect(cfg.apps["T"] == nil)
    }
}
