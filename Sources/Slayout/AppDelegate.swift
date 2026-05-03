import AppKit
import SlayoutCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let screens: ScreenProvider = NSScreenProvider()
    private lazy var server: WindowServer = WindowServerAX(screens: screens)
    private var config: Config = .default
    private var bindings: Bindings!
    private var executor: Executor!
    private var eventSource: EventSource?
    private var recorder: Recorder!
    private var lastLayout = LastLayoutSelector()
    private var tickTimer: Timer?
    private var configWatcher: DispatchSourceFileSystemObject?

    func applicationDidFinishLaunching(_ notification: Notification) {
        SlayoutLog.log("=== Slayout launching ===")
        SlayoutLog.log("Bundle: \(Bundle.main.bundlePath)")
        SlayoutLog.log("Accessibility granted: \(Permissions.hasAccessibility())")
        SlayoutLog.log("Input Monitoring granted: \(Permissions.hasInputMonitoring())")
        setupStatusItem()
        Permissions.requestAccessibilityIfNeeded()
        Permissions.requestInputMonitoringIfNeeded()
        loadConfigAndStart()
        observeScreenChanges()
        startTickTimer()
        watchConfigFile()
    }

    private func loadConfigAndStart() {
        config = ConfigPaths.loadOrCreate()
        bindings = Bindings(config: config)
        bindings.savedLayouts = LayoutStore.savedLayoutKeys()

        recorder = Recorder(
            captureSnapshot: { [server, screens] in
                LayoutCapture.capture(windows: server.allWindows(), screens: screens.screens)
            },
            saveLayout: { [bindings] key, snap in
                let url = ConfigPaths.layoutFile(forKey: key)
                try? LayoutStore.save(snap, to: url)
                bindings?.savedLayouts.insert(key)
            },
            isReserved: { [config] key in
                config.windows[key] != nil ||
                config.apps[key] != nil ||
                config.meta.record == key ||
                config.meta.restoreLast == key ||
                config.meta.reload == key
            }
        )

        executor = Executor(server: server, screens: screens, lookupBundleID: lookupBundleID(for:))
        executor.hooks.enterRecord = { [weak self] in self?.refreshStatusTitle() }
        executor.hooks.bindLayout = { [weak self] key in
            guard let self = self else { return }
            let result = self.recorder.bind(to: key)
            if case .aborted = result { NSSound.beep() }
            self.refreshStatusTitle()
        }
        executor.hooks.restoreLayout = { [weak self] key in
            self?.restoreLayout(key: key)
        }
        executor.hooks.restoreLast = { [weak self] in
            self?.restoreLast()
        }
        executor.hooks.reload = { [weak self] in self?.loadConfigAndStart() }

        if config.hyperTrigger == .capsLock {
            HyperKeySetup.remapCapsLockToF18()
        }
        let trigger = config.hyperTrigger.rawValue
        eventSource?.stop()
        let source = CGEventTapSource(triggerKey: trigger)
        eventSource = source
        source.start { [weak self] event in
            guard let self = self else { return false }
            let result = self.bindings.handle(event)
            if result.effect != .none {
                DispatchQueue.main.async { self.executor.run(result.effect) }
            }
            return result.consume
        }
        refreshStatusTitle()
    }

    private func restoreLayout(key: String) {
        let url = ConfigPaths.layoutFile(forKey: key)
        guard let snap = try? LayoutStore.load(from: url) else { return }
        applySnapshot(snap)
    }

    private func restoreLast() {
        guard let snap = lastLayout.snapshot(for: screens.screens) else { return }
        applySnapshot(snap)
    }

    private func applySnapshot(_ snap: LayoutSnapshot) {
        // Snap the live world once. Keeping the same WindowRef list ensures
        // server.setFrame finds a cached AX handle for each plan target.
        let live = server.allWindows()
        let plans = LayoutRestore.plan(snapshot: snap, current: live, screens: screens.screens)
        SlayoutLog.log("Slayout: applySnapshot: \(plans.count) plan(s) from \(snap.windows.count) snapshot windows over \(live.count) live windows")
        for plan in plans {
            server.setFrame(plan.frame, of: plan.window)
        }
    }

    private func startTickTimer() {
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let snap = LayoutCapture.capture(windows: self.server.allWindows(),
                                             screens: self.screens.screens)
            self.lastLayout.tick(snap)
        }
    }

    private func observeScreenChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParamsChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParamsChanged() {
        // The screens just changed; the next tick will re-fingerprint and start
        // a new stable window. No additional action required for v1.
        refreshStatusTitle()
    }

    private func watchConfigFile() {
        configWatcher?.cancel()
        let url = ConfigPaths.configFile
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            self?.loadConfigAndStart()
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        configWatcher = src
    }

    private func refreshStatusTitle() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let button = self.statusItem?.button else { return }
            // Show "●" alongside the icon while recording.
            button.title = self.bindings.isRecording ? "● " : ""
        }
    }

    private func lookupBundleID(for nameOrBundle: String) -> String? {
        if nameOrBundle.contains(".") { return nameOrBundle }
        for app in NSWorkspace.shared.runningApplications where app.localizedName == nameOrBundle {
            return app.bundleIdentifier
        }
        let path = "/Applications/\(nameOrBundle).app"
        if FileManager.default.fileExists(atPath: path),
           let bundle = Bundle(path: path),
           let id = bundle.bundleIdentifier {
            return id
        }
        return nil
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let url = Bundle.main.url(forResource: "MenubarIcon", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            img.isTemplate = true
            item.button?.image = img
        } else {
            item.button?.title = "S"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Slayout", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeItem("Reload Config", #selector(reload)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items where mi.action != nil { mi.target = self }
        item.menu = menu
        statusItem = item
    }

    private func makeItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func reload() { loadConfigAndStart() }
    @objc private func quit() { NSApp.terminate(nil) }
}
