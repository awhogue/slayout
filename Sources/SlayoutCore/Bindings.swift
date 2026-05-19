import Foundation

public struct KeyEvent: Equatable, Sendable {
    public enum Kind: Sendable { case keyDown, keyUp }
    public let kind: Kind
    public let key: String          // lowercased character or special name ("return","up","f18", etc.)
    public let isHyperTrigger: Bool // true if this key is the configured hyper trigger

    public init(kind: Kind, key: String, isHyperTrigger: Bool) {
        self.kind = kind
        self.key = key
        self.isHyperTrigger = isHyperTrigger
    }
}

public enum DispatchEffect: Equatable, Sendable {
    case none
    case windowAction(WindowAction)
    case focusApp(String)
    case enterRecord
    case bindLayout(String)
    case restoreLayout(String)
    case restoreLast
    case reload
}

public struct HandleResult: Equatable, Sendable {
    public let consume: Bool
    public let effect: DispatchEffect
}

/// Pure dispatch logic: tracks hyper state and maps `(hyper, key)` events to
/// `DispatchEffect`s. The caller is responsible for executing the effect.
public final class Bindings {
    public var config: Config
    public var savedLayouts: Set<String> = []
    public private(set) var isRecording: Bool = false
    private var hyperHeld: Bool = false

    public init(config: Config) {
        self.config = config
    }

    public func handle(_ event: KeyEvent) -> HandleResult {
        if event.isHyperTrigger {
            hyperHeld = (event.kind == .keyDown)
            return HandleResult(consume: true, effect: .none)
        }
        guard hyperHeld else {
            return HandleResult(consume: false, effect: .none)
        }
        // While hyper is held, swallow all events to prevent leaks to underlying apps.
        if event.kind != .keyDown {
            return HandleResult(consume: true, effect: .none)
        }
        let key = event.key.lowercased()

        // Recording mode: next hyper-key binds the current layout to that key.
        // Re-pressing the record key cancels.
        if isRecording {
            isRecording = false
            if key == config.meta.record {
                return HandleResult(consume: true, effect: .enterRecord)
            }
            return HandleResult(consume: true, effect: .bindLayout(key))
        }

        // Priority: window action > app > meta > saved layout > none.
        if let action = config.windows[key] {
            return HandleResult(consume: true, effect: .windowAction(action))
        }
        if let app = config.apps[key] {
            return HandleResult(consume: true, effect: .focusApp(app))
        }
        if config.meta.record == key {
            isRecording = true
            return HandleResult(consume: true, effect: .enterRecord)
        }
        if config.meta.restoreLast == key {
            return HandleResult(consume: true, effect: .restoreLast)
        }
        if config.meta.reload == key {
            return HandleResult(consume: true, effect: .reload)
        }
        if savedLayouts.contains(key) {
            return HandleResult(consume: true, effect: .restoreLayout(key))
        }
        SlayoutLog.vlog("Bindings: hyper+\"\(key)\" pressed but no binding matched")
        return HandleResult(consume: true, effect: .none)
    }
}
