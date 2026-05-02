import Foundation

public struct WindowState: Codable, Equatable, Sendable {
    public let bundleID: String
    public let appName: String
    public let title: String
    public let screenIndex: Int
    public let frame: CGRect

    public init(bundleID: String, appName: String, title: String, screenIndex: Int, frame: CGRect) {
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.screenIndex = screenIndex
        self.frame = frame
    }
}

public struct ScreenFingerprint: Codable, Equatable, Sendable {
    public let displayID: UInt32
    public let name: String
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let isBuiltin: Bool

    public init(displayID: UInt32, name: String, frame: CGRect, visibleFrame: CGRect, isBuiltin: Bool) {
        self.displayID = displayID
        self.name = name
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.isBuiltin = isBuiltin
    }
}

public struct LayoutSnapshot: Codable, Equatable, Sendable {
    public let windows: [WindowState]
    public let screens: [ScreenFingerprint]
    public let capturedAt: Date

    public init(windows: [WindowState], screens: [ScreenFingerprint], capturedAt: Date) {
        self.windows = windows
        self.screens = screens
        self.capturedAt = capturedAt
    }
}

public enum LayoutCapture {
    public static func capture(windows: [WindowRef], screens: [ScreenInfo], now: Date = Date()) -> LayoutSnapshot {
        let fingerprints = screens.map { ScreenFingerprint(displayID: $0.displayID, name: $0.name,
                                                           frame: $0.frame, visibleFrame: $0.visibleFrame,
                                                           isBuiltin: $0.isBuiltin) }
        var states: [WindowState] = []
        for w in windows {
            let idx = screens.firstIndex(where: { $0.displayID == w.screenID }) ?? 0
            states.append(WindowState(bundleID: w.bundleID, appName: w.appName, title: w.title,
                                      screenIndex: idx, frame: w.frame))
        }
        return LayoutSnapshot(windows: states, screens: fingerprints, capturedAt: now)
    }
}

public enum LayoutRestore {
    public struct Plan: Equatable {
        public let window: WindowRef
        public let frame: CGRect
    }

    public static func plan(snapshot: LayoutSnapshot,
                            current: [WindowRef],
                            screens: [ScreenInfo]) -> [Plan] {
        var plans: [Plan] = []
        var claimed: Set<UInt32> = []

        for state in snapshot.windows {
            guard let live = matchWindow(state: state, in: current, claimed: claimed) else { continue }
            claimed.insert(live.id)
            let targetFrame = resolveTargetFrame(for: state, snapshot: snapshot, screens: screens)
            plans.append(Plan(window: live, frame: targetFrame))
        }
        return plans
    }

    private static func matchWindow(state: WindowState, in candidates: [WindowRef], claimed: Set<UInt32>) -> WindowRef? {
        let unclaimed = candidates.filter { !claimed.contains($0.id) && $0.bundleID == state.bundleID }
        if unclaimed.isEmpty { return nil }
        if let exact = unclaimed.first(where: { $0.title == state.title }) { return exact }
        if let prefix = unclaimed
            .filter({ !$0.title.isEmpty && !state.title.isEmpty })
            .max(by: { commonPrefixLength($0.title, state.title) < commonPrefixLength($1.title, state.title) }),
           commonPrefixLength(prefix.title, state.title) > 0 {
            return prefix
        }
        return unclaimed.first
    }

    private static func commonPrefixLength(_ a: String, _ b: String) -> Int {
        var count = 0
        var ai = a.startIndex, bi = b.startIndex
        while ai < a.endIndex, bi < b.endIndex, a[ai] == b[bi] {
            ai = a.index(after: ai); bi = b.index(after: bi); count += 1
        }
        return count
    }

    private static func resolveTargetFrame(for state: WindowState,
                                           snapshot: LayoutSnapshot,
                                           screens: [ScreenInfo]) -> CGRect {
        guard snapshot.screens.indices.contains(state.screenIndex) else { return state.frame }
        let captured = snapshot.screens[state.screenIndex]
        let liveScreen: ScreenInfo? =
            screens.first(where: { $0.displayID == captured.displayID }) ??
            (screens.indices.contains(state.screenIndex) ? screens[state.screenIndex] : nil) ??
            screens.first
        guard let live = liveScreen else { return state.frame }

        if live.visibleFrame == captured.visibleFrame {
            return state.frame
        }
        // Map proportionally from the captured screen's visibleFrame onto the live screen's.
        let svf = captured.visibleFrame
        let tvf = live.visibleFrame
        guard svf.width > 0, svf.height > 0 else { return state.frame }
        let fx = (state.frame.minX - svf.minX) / svf.width
        let fy = (state.frame.minY - svf.minY) / svf.height
        let fw = state.frame.width / svf.width
        let fh = state.frame.height / svf.height
        return CGRect(x: tvf.minX + fx * tvf.width,
                      y: tvf.minY + fy * tvf.height,
                      width: fw * tvf.width,
                      height: fh * tvf.height)
    }
}

public enum LayoutStore {
    public static func encode(_ snap: LayoutSnapshot) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(snap)
    }

    public static func decode(_ data: Data) throws -> LayoutSnapshot {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(LayoutSnapshot.self, from: data)
    }

    public static func save(_ snap: LayoutSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try encode(snap).write(to: url, options: .atomic)
    }

    public static func load(from url: URL) throws -> LayoutSnapshot {
        let data = try Data(contentsOf: url)
        return try decode(data)
    }

    /// Enumerate the keys (filenames without ".json") of stored user-recorded layouts.
    public static func savedLayoutKeys() -> Set<String> {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: ConfigPaths.layoutsDir,
                                                     includingPropertiesForKeys: nil) else { return [] }
        return Set(urls.compactMap { url in
            url.pathExtension == "json" ? url.deletingPathExtension().lastPathComponent : nil
        })
    }
}
