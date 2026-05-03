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
    private let debug: Bool

    public init(triggerKey: String, debug: Bool = ProcessInfo.processInfo.environment["SLAYOUT_DEBUG"] == "1") {
        self.triggerKey = HyperKeySetup.effectiveTriggerKey(triggerKey)
        self.debug = debug
        SlayoutLog.log("Slayout: CGEventTapSource init triggerKey=\(self.triggerKey) (configured \(triggerKey)), debug=\(debug)")
    }

    public func start(handler: @escaping (KeyEvent) -> Bool) {
        self.handler = handler
        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)
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
            SlayoutLog.log("Slayout: FAILED to create event tap. Input Monitoring (and possibly Accessibility) not granted to this binary?")
            return
        }
        let rls = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), rls, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        self.tap = port
        self.runLoopSource = rls
        SlayoutLog.log("Slayout: event tap created and enabled")
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
        if type == .flagsChanged {
            return handleFlagsChanged(keyCode: keyCode, event: event, handler: handler)
        }
        guard let key = KeyCodes.keyString(for: keyCode) else {
            if debug { SlayoutLog.log("Slayout: key event keyCode=\(keyCode) (no mapping)") }
            return Unmanaged.passUnretained(event)
        }
        let kind: KeyEvent.Kind = (type == .keyDown) ? .keyDown : .keyUp
        let isHyper = key == triggerKey
        let ke = KeyEvent(kind: kind, key: key, isHyperTrigger: isHyper)
        let consume = handler(ke)
        if debug {
            SlayoutLog.log("Slayout: keyCode=\(keyCode) key=\(key) kind=\(kind) hyperTrigger=\(isHyper) consumed=\(consume)")
        }
        return consume ? nil : Unmanaged.passUnretained(event)
    }

    /// Per-modifier press state tracked across flagsChanged events.
    private var modifierPressed: [String: Bool] = [:]

    private func handleFlagsChanged(keyCode: Int, event: CGEvent,
                                    handler: (KeyEvent) -> Bool) -> Unmanaged<CGEvent>? {
        guard let key = KeyCodes.keyString(for: keyCode), KeyCodes.isModifier(key) else {
            if debug {
                SlayoutLog.log("Slayout: flagsChanged keyCode=\(keyCode) (unmapped or not a modifier)")
            }
            return Unmanaged.passUnretained(event)
        }
        let flags = event.flags.rawValue
        // Determine press vs release: if the modifier's mask is set in flags it's a press,
        // unless the same key was already pressed (then it's a release on second toggle).
        let mask = KeyCodes.flagMask(for: key) ?? 0
        let modifierActive = (flags & mask) != 0
        let wasPressed = modifierPressed[key] ?? false
        let isPressed: Bool
        if modifierActive && !wasPressed {
            isPressed = true
        } else if !modifierActive && wasPressed {
            isPressed = false
        } else {
            // Edge case: both left+right of the same modifier; left was held, right just changed.
            // Use a heuristic: keyCode disambiguates left/right, so toggle this specific key's state.
            isPressed = !wasPressed
        }
        modifierPressed[key] = isPressed
        let kind: KeyEvent.Kind = isPressed ? .keyDown : .keyUp
        let isHyper = key == triggerKey
        let ke = KeyEvent(kind: kind, key: key, isHyperTrigger: isHyper)
        let consume = handler(ke)
        if debug {
            SlayoutLog.log("Slayout: flagsChanged keyCode=\(keyCode) key=\(key) kind=\(kind) flags=0x\(String(flags, radix: 16)) hyperTrigger=\(isHyper) consumed=\(consume)")
        }
        return consume ? nil : Unmanaged.passUnretained(event)
    }
}
