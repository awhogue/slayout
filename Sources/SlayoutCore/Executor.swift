import Foundation

/// Hooks for meta-effects that aren't yet implemented (Recorder, LastLayoutWatcher,
/// config reload). Step 1 wires no-op closures; later steps fill them in.
public struct ExecutorHooks {
    public var enterRecord: () -> Void = {}
    public var bindLayout: (String) -> Void = { _ in }
    public var restoreLayout: (String) -> Void = { _ in }
    public var restoreLast: () -> Void = {}
    public var reload: () -> Void = {}
    public init() {}
}

/// Translates `DispatchEffect`s into real WindowServer + hook calls.
public final class Executor {
    private let server: WindowServer
    private let screens: ScreenProvider
    public var hooks: ExecutorHooks
    public var lookupBundleID: (String) -> String?

    public init(server: WindowServer,
                screens: ScreenProvider,
                hooks: ExecutorHooks = ExecutorHooks(),
                lookupBundleID: @escaping (String) -> String? = { _ in nil }) {
        self.server = server
        self.screens = screens
        self.hooks = hooks
        self.lookupBundleID = lookupBundleID
    }

    public func run(_ effect: DispatchEffect) {
        switch effect {
        case .none:
            return
        case .windowAction(let action):
            guard let win = server.frontmostWindow() else { return }
            try? Actions.apply(action, to: win, server: server, screens: screens.screens)
        case .focusApp(let nameOrBundle):
            let bundleID = lookupBundleID(nameOrBundle) ?? nameOrBundle
            server.focus(bundleID: bundleID)
        case .enterRecord:
            hooks.enterRecord()
        case .bindLayout(let key):
            hooks.bindLayout(key)
        case .restoreLayout(let key):
            hooks.restoreLayout(key)
        case .restoreLast:
            hooks.restoreLast()
        case .reload:
            hooks.reload()
        }
    }
}
