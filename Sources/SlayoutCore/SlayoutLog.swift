import Foundation

/// Writes log lines to ~/Library/Logs/Slayout/slayout.log AND stderr.
/// Plain old file logging — guaranteed visible regardless of how the app was launched.
public enum SlayoutLog {
    private static let lock = NSLock()
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    private static let verboseDefaultsKey = "SlayoutVerboseLogging"

    /// When true, `vlog(_:)` writes to the log. Toggled from the menubar.
    /// Persisted across launches via UserDefaults.
    public static var verbose: Bool {
        get { UserDefaults.standard.bool(forKey: verboseDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: verboseDefaultsKey) }
    }

    public static var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/Slayout/slayout.log")
    }

    public static func log(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(formatter.string(from: Date())) \(message)\n"
        FileHandle.standardError.write(line.data(using: .utf8) ?? Data())
        appendToFile(line)
    }

    /// Verbose-only log line. Cheap when verbose is off (the message closure
    /// isn't evaluated). Use for per-keystroke / per-window diagnostics.
    public static func vlog(_ message: @autoclosure () -> String) {
        guard verbose else { return }
        log("[v] \(message())")
    }

    private static func appendToFile(_ line: String) {
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        guard let h = try? FileHandle(forWritingTo: url) else { return }
        defer { try? h.close() }
        h.seekToEndOfFile()
        h.write(line.data(using: .utf8) ?? Data())
    }
}
