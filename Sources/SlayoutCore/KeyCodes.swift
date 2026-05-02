import Foundation

/// Maps Carbon virtual keycodes to Slayout's string key identifiers.
/// Letter/number keys produce their lowercased character; punctuation and
/// special keys produce stable names like "return", "up", "[", "f18".
public enum KeyCodes {
    public static func keyString(for keyCode: Int) -> String? { table[keyCode] }
    public static func keyCode(for keyString: String) -> Int? { reverse[keyString.lowercased()] }

    private static let table: [Int: String] = [
        // Letters (Carbon kVK_ANSI_*)
        0x00: "a", 0x01: "s", 0x02: "d", 0x03: "f", 0x04: "h",
        0x05: "g", 0x06: "z", 0x07: "x", 0x08: "c", 0x09: "v",
        0x0B: "b", 0x0C: "q", 0x0D: "w", 0x0E: "e", 0x0F: "r",
        0x10: "y", 0x11: "t", 0x1F: "o", 0x20: "u", 0x22: "i",
        0x23: "p", 0x25: "l", 0x26: "j", 0x28: "k", 0x2D: "n",
        0x2E: "m",
        // Numbers
        0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x17: "5",
        0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9", 0x1D: "0",
        // Punctuation
        0x18: "=", 0x1B: "-", 0x1E: "]", 0x21: "[",
        0x27: "'", 0x29: ";", 0x2A: "\\", 0x2B: ",",
        0x2C: "/", 0x2F: ".", 0x32: "`",
        // Whitespace / editing
        0x24: "return", 0x30: "tab", 0x31: "space", 0x33: "delete",
        0x35: "escape",
        // Arrows
        0x7B: "left", 0x7C: "right", 0x7D: "down", 0x7E: "up",
        // Function keys
        0x7A: "f1", 0x78: "f2", 0x63: "f3", 0x76: "f4",
        0x60: "f5", 0x61: "f6", 0x62: "f7", 0x64: "f8",
        0x65: "f9", 0x6D: "f10", 0x67: "f11", 0x6F: "f12",
        0x69: "f13", 0x6B: "f14", 0x71: "f15", 0x6A: "f16",
        0x40: "f17", 0x4F: "f18", 0x50: "f19", 0x5A: "f20",
    ]

    private static let reverse: [String: Int] = {
        var m: [String: Int] = [:]
        for (k, v) in table { m[v] = k }
        return m
    }()
}
