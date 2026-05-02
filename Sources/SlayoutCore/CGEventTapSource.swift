import AppKit
import CoreGraphics

/// `EventSource` backed by a CGEventTap. Listens for keyDown/keyUp and emits
/// `KeyEvent`s with `isHyperTrigger` set when the keycode matches the
/// configured hyper trigger (after caps-lock-to-F18 remap, the trigger is F18).
public final class CGEventTapSource: EventSource {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var handler: ((KeyEvent) -> Bool)?
    private let triggerKey: String

    /// `triggerKey` is the Slayout key string for the hyper trigger ("f18", "right_cmd"...).
    /// `caps_lock` should be remapped to `f18` via `HyperKeySetup.remapCapsLockToF18()` first.
    public init(triggerKey: String) {
        self.triggerKey = HyperKeySetup.effectiveTriggerKey(triggerKey)
    }

    public func start(handler: @escaping (KeyEvent) -> Bool) {
        self.handler = handler
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)
        let observer = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let me = Unmanaged<CGEventTapSource>.fromOpaque(refcon).takeUnretainedValue()
                return me.dispatch(proxy: proxy, type: type, event: event)
            },
            userInfo: observer
        ) else {
            NSLog("Slayout: failed to create event tap. Input Monitoring not granted?")
            return
        }
        let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), rls, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.tap = port
        self.runLoopSource = rls
    }

    public func stop() {
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let rls = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), rls, .commonModes) }
        tap = nil
        runLoopSource = nil
        handler = nil
    }

    private func dispatch(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable the tap if it was disabled by the system (e.g. timeout).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard let handler = handler else { return Unmanaged.passUnretained(event) }
        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        guard let key = KeyCodes.keyString(for: keyCode) else {
            return Unmanaged.passUnretained(event)
        }
        let kind: KeyEvent.Kind = (type == .keyDown) ? .keyDown : .keyUp
        let ke = KeyEvent(kind: kind, key: key, isHyperTrigger: key == triggerKey)
        let consume = handler(ke)
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
