import AppKit
import SlayoutCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        Permissions.requestAccessibilityIfNeeded()
        if !Permissions.hasInputMonitoring() {
            Permissions.openInputMonitoringSettings()
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "S"
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Slayout (idle)", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        for mi in menu.items where mi.action != nil { mi.target = self }
        item.menu = menu
        statusItem = item
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
