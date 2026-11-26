import Foundation

/// Launch at login through a per-user LaunchAgent. This works for unsigned builds,
/// shows up under System Settings > General > Login Items, and survives app updates.
enum LoginItem {
    static let label = "com.thomasmelak.lidblur"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            let plist: [String: Any] = [
                "Label": label,
                "ProgramArguments": ["/usr/bin/open", "-g", Bundle.main.bundlePath],
                "RunAtLoad": true,
                "LimitLoadToSessionType": "Aqua",
                "ProcessType": "Interactive",
            ]
            try FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
        } else if isEnabled {
            try FileManager.default.removeItem(at: plistURL)
        }
    }
}
