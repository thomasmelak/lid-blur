import AppKit

/// Removes Lid Blur from inside the app: login item, settings, and the app itself (to the Trash).
@MainActor
enum Uninstaller {
    static func confirmAndUninstall() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall Lid Blur?"
        alert.informativeText = "This removes the login item and settings, and moves Lid Blur to the Trash."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        try? LoginItem.setEnabled(false)
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }

        let bundleURL = Bundle.main.bundleURL
        if bundleURL.pathExtension == "app" {
            NSWorkspace.shared.recycle([bundleURL]) { _, _ in
                Task { @MainActor in NSApp.terminate(nil) }
            }
        } else {
            NSApp.terminate(nil)
        }
    }
}
