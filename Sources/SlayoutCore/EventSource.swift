import Foundation

/// Abstracts a stream of `KeyEvent`s. The real implementation wraps a
/// `CGEventTap`; tests inject events directly.
public protocol EventSource {
    /// Start delivering events to `handler`. The handler returns `true` to
    /// consume the event (i.e. swallow it from the system input chain) or
    /// `false` to pass it through.
    func start(handler: @escaping (KeyEvent) -> Bool)
    func stop()
}
