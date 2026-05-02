import Foundation

public enum ConfigPaths {
    public static var configDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/slayout", isDirectory: true)
    }

    public static var configFile: URL { configDir.appendingPathComponent("config.toml") }
    public static var layoutsFile: URL { configDir.appendingPathComponent("layouts.toml") }
    public static var layoutsDir: URL { configDir.appendingPathComponent("layouts", isDirectory: true) }
    public static func layoutFile(forKey key: String) -> URL {
        layoutsDir.appendingPathComponent("\(key).json")
    }

    public static let defaultConfigTOML = """
    [hyper]
    trigger = "caps_lock"   # caps_lock | right_cmd | right_option | f19

    [apps]
    # Hyper + key = focus this app
    T = "Terminal"
    C = "Google Chrome"

    [window]
    # Hyper + key = built-in window action
    "return" = "fullscreen"
    "[" = "left-two-thirds"
    "]" = "right-two-thirds"
    "h" = "left-half"
    "l" = "right-half"
    "k" = "top-half"
    "j" = "bottom-half"
    "up" = "screen:external"
    "down" = "screen:builtin"

    [meta]
    record = "s"
    restore_last = "z"
    reload = "r"
    """

    /// Read the config from disk, creating a default if absent. Never throws —
    /// returns Config.default on read or parse error.
    @discardableResult
    public static func loadOrCreate() -> Config {
        let fm = FileManager.default
        try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: configFile.path) {
            try? defaultConfigTOML.write(to: configFile, atomically: true, encoding: .utf8)
        }
        guard let data = try? String(contentsOf: configFile, encoding: .utf8) else {
            return .default
        }
        do {
            return try ConfigLoader.parse(data)
        } catch {
            NSLog("Slayout: failed to parse config: \(error). Using defaults.")
            return .default
        }
    }
}
