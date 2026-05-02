import Foundation

/// Tracks the most recent stable layout for each unique screen fingerprint.
/// Pure logic; tests inject a custom clock.
public final class LastLayoutSelector {
    public private(set) var stableByFingerprint: [String: LayoutSnapshot] = [:]

    private let stableInterval: TimeInterval
    private let clock: () -> Date
    private var pendingFingerprint: String?
    private var pendingSince: Date = .distantPast

    public init(stableInterval: TimeInterval = 5.0, clock: @escaping () -> Date = { Date() }) {
        self.stableInterval = stableInterval
        self.clock = clock
    }

    /// Feed a fresh snapshot. Once a fingerprint has been observed continuously
    /// for `stableInterval`, the most recent snapshot is stored as the "stable"
    /// entry for that fingerprint.
    public func tick(_ snap: LayoutSnapshot) {
        let fp = Self.fingerprint(snap.screens)
        let now = clock()
        if pendingFingerprint != fp {
            pendingFingerprint = fp
            pendingSince = now
        }
        if now.timeIntervalSince(pendingSince) >= stableInterval {
            stableByFingerprint[fp] = snap
        }
    }

    /// Look up the stored snapshot for the current screen configuration.
    public func snapshot(for screens: [ScreenInfo]) -> LayoutSnapshot? {
        stableByFingerprint[Self.fingerprint(screens)]
    }

    public static func fingerprint(_ screens: [ScreenFingerprint]) -> String {
        screens.map { "\($0.displayID):\(rectKey($0.frame))" }.joined(separator: "|")
    }

    public static func fingerprint(_ screens: [ScreenInfo]) -> String {
        screens.map { "\($0.displayID):\(rectKey($0.frame))" }.joined(separator: "|")
    }

    private static func rectKey(_ r: CGRect) -> String {
        "\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height))"
    }
}
