import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let settings = Settings.shared
    private let controller = LidBlurController()
    private var statusItem: NSStatusItem?
    private let statusLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var menuTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !settings.hasLaunchedBefore {
            settings.hasLaunchedBefore = true
            try? LoginItem.setEnabled(true)
        } else if LoginItem.isEnabled {
            // Keep the login item pointing at wherever the app lives now.
            try? LoginItem.setEnabled(true)
        }

        setUpStatusItem()
        controller.start()
    }

    // MARK: - Menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: "Lid Blur")
            image?.isTemplate = true
            button.image = image
        }
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        item.menu = menu
        statusItem = item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        statusLine.isEnabled = false
        updateStatusLine()
        menu.addItem(statusLine)
        menu.addItem(.separator())

        menu.addItem(item("Enabled", #selector(toggleEnabled), checked: settings.enabled))
        menu.addItem(item("Preview Animation", #selector(preview), enabled: settings.enabled))
        menu.addItem(.separator())

        let styleMenu = NSMenu()
        for style in BlurStyle.allCases {
            let entry = item(style.title, #selector(chooseStyle(_:)), checked: settings.style == style)
            entry.representedObject = style.rawValue
            styleMenu.addItem(entry)
        }
        menu.addItem(submenu("Style", styleMenu))

        let intensityMenu = NSMenu()
        for intensity in Intensity.allCases {
            let entry = item(intensity.title, #selector(chooseIntensity(_:)), checked: settings.intensity == intensity)
            entry.representedObject = intensity.rawValue
            intensityMenu.addItem(entry)
        }
        menu.addItem(submenu("Intensity", intensityMenu))

        let angleMenu = NSMenu()
        for angle in Settings.clearAngleChoices {
            let entry = item("\(Int(angle))°", #selector(chooseClearAngle(_:)), checked: settings.clearAngle == angle)
            entry.representedObject = angle
            entry.isEnabled = controller.hasSensor
            angleMenu.addItem(entry)
        }
        menu.addItem(submenu("Sharp From Lid Angle", angleMenu))

        menu.addItem(.separator())
        menu.addItem(item("Launch at Login", #selector(toggleLaunchAtLogin), checked: LoginItem.isEnabled))
        menu.addItem(.separator())
        let quit = item("Quit Lid Blur", #selector(quit))
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        let timer = Timer(timeInterval: 0.2, target: self, selector: #selector(updateStatusLine),
                          userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        menuTimer = timer
    }

    func menuDidClose(_ menu: NSMenu) {
        menuTimer?.invalidate()
        menuTimer = nil
    }

    @objc private func updateStatusLine() {
        if controller.hasSensor {
            if let angle = controller.currentAngle {
                statusLine.title = "Lid angle: \(Int(angle.rounded()))°"
            } else {
                statusLine.title = "Lid angle: reading…"
            }
        } else {
            statusLine.title = "No lid angle sensor: using open/close events"
        }
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, enabled: Bool = true) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.state = checked ? .on : .off
        entry.isEnabled = enabled
        return entry
    }

    private func submenu(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = submenu
        return entry
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        settings.enabled.toggle()
        controller.settingsChanged()
    }

    @objc private func preview() {
        controller.preview()
    }

    @objc private func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let style = BlurStyle(rawValue: raw) else { return }
        settings.style = style
        controller.preview()
    }

    @objc private func chooseIntensity(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let intensity = Intensity(rawValue: raw) else { return }
        settings.intensity = intensity
        controller.preview()
    }

    @objc private func chooseClearAngle(_ sender: NSMenuItem) {
        guard let angle = sender.representedObject as? Double else { return }
        settings.clearAngle = angle
        controller.settingsChanged()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isEnabled)
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
