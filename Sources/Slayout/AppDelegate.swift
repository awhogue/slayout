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
        let result = ConfigPaths.loadOrCreateWithWarnings()
        config = result.config
        if !result.warnings.isEmpty { presentConfigWarnings(result.warnings) }
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
        // Treat anything that looks like reverse-DNS (multiple dots) as a bundle ID.
        if nameOrBundle.contains(".") && !nameOrBundle.hasSuffix(".us") {
            return nameOrBundle
        }
        let target = nameOrBundle.lowercased()
        for app in NSWorkspace.shared.runningApplications {
            if app.localizedName?.lowercased() == target { return app.bundleIdentifier }
        }
        // Direct path match first (fast path for normal apps).
        let direct = "/Applications/\(nameOrBundle).app"
        if FileManager.default.fileExists(atPath: direct),
           let bundle = Bundle(path: direct),
           let id = bundle.bundleIdentifier {
            return id
        }
        // Fallback: scan /Applications for any .app whose CFBundleName,
        // CFBundleDisplayName, or filename matches (case-insensitive). This
        // catches apps whose on-disk filename differs from their display name —
        // e.g. "Zoom Workplace" lives at /Applications/zoom.us.app.
        if let id = scanApplicationsForBundleID(matching: target) { return id }
        SlayoutLog.log("Slayout: lookupBundleID: no match for \"\(nameOrBundle)\"")
        return nil
    }

    private func scanApplicationsForBundleID(matching target: String) -> String? {
        let roots = ["/Applications", "/Applications/Utilities",
                     (NSHomeDirectory() as NSString).appendingPathComponent("Applications")]
        let fm = FileManager.default
        struct Candidate { let bundleID: String; let displayLen: Int; let kind: String; let path: String }
        var exact: [Candidate] = []
        var prefix: [Candidate] = []
        var substr: [Candidate] = []
        for root in roots {
            guard let entries = try? fm.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = "\(root)/\(entry)"
                guard let bundle = Bundle(path: path), let bid = bundle.bundleIdentifier else { continue }
                let filename = (entry as NSString).deletingPathExtension.lowercased()
                let info = bundle.infoDictionary ?? [:]
                let name = (info["CFBundleName"] as? String)?.lowercased() ?? ""
                let display = (info["CFBundleDisplayName"] as? String)?.lowercased() ?? ""
                let execName = (info["CFBundleExecutable"] as? String)?.lowercased() ?? ""
                let fields = [filename, name, display, execName].filter { !$0.isEmpty }
                let len = (display.isEmpty ? (name.isEmpty ? filename : name) : display).count
                let c = Candidate(bundleID: bid, displayLen: len, kind: "", path: path)
                if fields.contains(where: { $0 == target }) {
                    exact.append(c); continue
                }
                if target.count >= 2, fields.contains(where: { $0.hasPrefix(target) }) {
                    prefix.append(c); continue
                }
                if target.count >= 3, fields.contains(where: { $0.contains(target) }) {
                    substr.append(c)
                }
            }
        }
        // Pick best: exact > prefix > substring; within a tier, shortest display name (most specific match).
        let pick: (Candidate) -> String = { c in
            SlayoutLog.log("Slayout: lookupBundleID: matched \"\(target)\" -> \(c.bundleID) at \(c.path)")
            return c.bundleID
        }
        if let c = exact.min(by: { $0.displayLen < $1.displayLen }) { return pick(c) }
        if let c = prefix.min(by: { $0.displayLen < $1.displayLen }) { return pick(c) }
        if let c = substr.min(by: { $0.displayLen < $1.displayLen }) { return pick(c) }
        return nil
    }

    private func presentConfigWarnings(_ warnings: [String]) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Slayout config has \(warnings.count) issue\(warnings.count == 1 ? "" : "s")"
            alert.informativeText = warnings.joined(separator: "\n") + "\n\nThe rest of your config has been loaded."
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.addButton(withTitle: "Open Config")
            NSApp.activate(ignoringOtherApps: true)
            let resp = alert.runModal()
            if resp == .alertSecondButtonReturn {
                NSWorkspace.shared.open(ConfigPaths.configFile)
            }
        }
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
        menu.addItem(makeItem("Open Config…", #selector(openConfig)))
        menu.addItem(.separator())
        let verboseItem = NSMenuItem(title: "Verbose Logging",
                                     action: #selector(toggleVerbose),
                                     keyEquivalent: "")
        verboseItem.state = SlayoutLog.verbose ? .on : .off
        verboseItem.target = self
        menu.addItem(verboseItem)
        menu.addItem(makeItem("Open Log File…", #selector(openLog)))
        menu.addItem(makeItem("Reveal Log in Finder", #selector(revealLog)))
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

    @objc private func openConfig(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(ConfigPaths.configFile)
    }

    @objc private func openLog(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(SlayoutLog.fileURL)
    }

    @objc private func revealLog(_ sender: NSMenuItem) {
        NSWorkspace.shared.activateFileViewerSelecting([SlayoutLog.fileURL])
    }

    @objc private func toggleVerbose(_ sender: NSMenuItem) {
        SlayoutLog.verbose.toggle()
        sender.state = SlayoutLog.verbose ? .on : .off
        SlayoutLog.log("Slayout: verbose logging \(SlayoutLog.verbose ? "ENABLED" : "disabled")")
    }
}
