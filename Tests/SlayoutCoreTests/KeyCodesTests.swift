import Testing
@testable import SlayoutCore

@Suite("KeyCodes mapping")
struct KeyCodesTests {
    @Test func tRoundTrip() {
        #expect(KeyCodes.keyString(for: 0x11) == "t")
        #expect(KeyCodes.keyCode(for: "t") == 0x11)
    }
    @Test func returnRoundTrip() {
        #expect(KeyCodes.keyString(for: 0x24) == "return")
        #expect(KeyCodes.keyCode(for: "return") == 0x24)
    }
    @Test func leftBracketRoundTrip() {
        #expect(KeyCodes.keyString(for: 0x21) == "[")
        #expect(KeyCodes.keyCode(for: "[") == 0x21)
    }
    @Test func upArrowRoundTrip() {
        #expect(KeyCodes.keyString(for: 0x7E) == "up")
        #expect(KeyCodes.keyCode(for: "up") == 0x7E)
    }
    @Test func f18RoundTrip() {
        #expect(KeyCodes.keyString(for: 0x4F) == "f18")
        #expect(KeyCodes.keyCode(for: "f18") == 0x4F)
    }
    @Test func unknownKeyCode() {
        #expect(KeyCodes.keyString(for: 0xFF) == nil)
    }
}

@Suite("HyperKeySetup")
struct HyperKeySetupTests {
    @Test func capsLockMapsToF18() {
        #expect(HyperKeySetup.effectiveTriggerKey("caps_lock") == "f18")
    }
    @Test func otherTriggersPassThrough() {
        #expect(HyperKeySetup.effectiveTriggerKey("right_cmd") == "right_cmd")
        #expect(HyperKeySetup.effectiveTriggerKey("f19") == "f19")
    }
}
