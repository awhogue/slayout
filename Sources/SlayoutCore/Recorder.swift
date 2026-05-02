import Foundation

public enum BindResult: Equatable, Sendable {
    case bound(key: String)
    case aborted(reason: String)
}

/// Captures the current window layout and persists it under a key.
/// State is handled in `Bindings.isRecording`; this type is the action handler.
public final class Recorder {
    private let captureSnapshot: () -> LayoutSnapshot
    private let saveLayout: (String, LayoutSnapshot) -> Void
    private let isReserved: (String) -> Bool

    public init(captureSnapshot: @escaping () -> LayoutSnapshot,
                saveLayout: @escaping (String, LayoutSnapshot) -> Void,
                isReserved: @escaping (String) -> Bool) {
        self.captureSnapshot = captureSnapshot
        self.saveLayout = saveLayout
        self.isReserved = isReserved
    }

    @discardableResult
    public func bind(to key: String) -> BindResult {
        if isReserved(key) {
            return .aborted(reason: "key '\(key)' is already bound to a config action")
        }
        let snap = captureSnapshot()
        saveLayout(key, snap)
        return .bound(key: key)
    }
}
