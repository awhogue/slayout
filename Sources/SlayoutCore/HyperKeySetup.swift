import Foundation

/// Caps-lock remap and trigger-name normalization.
///
/// macOS toggles caps lock state at the HID layer, so the standard trick is to
/// remap caps-lock to F18 via `hidutil`. After that, the event tap watches for
/// F18 instead of caps-lock.
public enum HyperKeySetup {
    /// HID Usage IDs for keys we may need to remap.
    private static let capsLockHID: UInt64 = 0x700000039
    private static let f18HID: UInt64 = 0x70000006D

    /// Translate a configured trigger key into the key string that the event
    /// tap will actually see. `caps_lock` is mapped to `f18` because we remap
    /// caps-lock at the HID layer.
    public static func effectiveTriggerKey(_ configured: String) -> String {
        switch configured {
        case "caps_lock": return "f18"
        default: return configured
        }
    }

    /// Apply the caps-lock-to-F18 HID remap for the current login session.
    /// Must be called once at app launch (before the event tap starts) when
    /// the user has chosen `caps_lock` as the hyper trigger.
    @discardableResult
    public static func remapCapsLockToF18() -> Bool {
        let mapping = #"{"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":\#(capsLockHID),"HIDKeyboardModifierMappingDst":\#(f18HID)}]}"#
        let task = Process()
        task.launchPath = "/usr/bin/hidutil"
        task.arguments = ["property", "--set", mapping]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            NSLog("Slayout: hidutil remap failed: \(error)")
            return false
        }
    }
}
