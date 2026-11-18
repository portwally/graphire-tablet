import AppKit
import SwiftUI

@main
enum Main {
    static let delegate = AppDelegate()
    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        app.setActivationPolicy(.accessory)   // menu-bar only, no Dock icon
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let driver = TabletDriver()
    private let state = TabletState.shared
    private var statusItem: NSStatusItem!
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.write("Graphire Tablet \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") starting")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "Graphire Tablet")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        // Posting pointer events needs Accessibility access.
        if !CGPreflightPostEventAccess() { CGRequestPostEventAccess() }
        refreshPermission()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refreshPermission()
        }

        driver.start()

        let d = UserDefaults.standard
        if !d.bool(forKey: "launchedBefore") {
            d.set(true, forKey: "launchedBefore")
            LoginItem.set(true)
            showSettings()
        }
    }

    /// Opening the app again (Finder, Spotlight, `open`) shows the settings window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    private func refreshPermission() {
        // CGPreflightPostEventAccess can stay stale until relaunch; AXIsProcessTrusted updates live.
        let granted = CGPreflightPostEventAccess() || AXIsProcessTrusted()
        if granted != state.accessibilityGranted {
            state.accessibilityGranted = granted
            Log.write("accessibility granted: \(granted)")
        }
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        switch state.connection {
        case .connected: status = "Graphire: Connected"
        case .searching: status = "Graphire: Not Connected"
        case .failed: status = "Graphire: Error (see Settings)"
        }
        menu.addItem(NSMenuItem(title: status, action: nil, keyEquivalent: ""))

        if !state.accessibilityGranted {
            let item = NSMenuItem(title: "Allow Accessibility Access…", action: #selector(openPrivacy), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if wacomDriverRunning() {
            menu.addItem(NSMenuItem(title: "⚠︎ Wacom driver is running (conflict)", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Graphire Tablet", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func wacomDriverRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            ($0.bundleIdentifier ?? "").lowercased().contains("wacom")
        }
    }

    @objc private func openPrivacy() { Privacy.openAccessibility() }

    @objc private func toggleLogin() { LoginItem.set(!LoginItem.isEnabled) }

    @objc func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Graphire Tablet"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
