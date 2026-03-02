import AppKit

/// Discovers all installed applications for the app launcher feature.
@MainActor
class AppCatalog {
    static let shared = AppCatalog()

    struct InstalledApp {
        let name: String
        let bundleID: String
        let bundleURL: URL
        let icon: NSImage?
    }

    private var cache: [InstalledApp] = []
    private var lastRefresh: Date = .distantPast

    private init() {}

    func allInstalledApps() -> [InstalledApp] {
        if cache.isEmpty || Date().timeIntervalSince(lastRefresh) > 60 {
            refresh()
        }
        return cache
    }

    func refresh() {
        let searchDirs = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]

        var apps: [InstalledApp] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for dir in searchDirs {
            guard let contents = try? fm.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil,
                options: []
            ) else { continue }

            for url in contents where url.pathExtension == "app" && !url.lastPathComponent.hasPrefix(".") {
                guard let bundle = Bundle(url: url),
                      let bundleID = bundle.bundleIdentifier,
                      !seen.contains(bundleID) else { continue }
                seen.insert(bundleID)

                let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                    ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                    ?? url.deletingPathExtension().lastPathComponent
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                apps.append(InstalledApp(name: name, bundleID: bundleID, bundleURL: url, icon: icon))
            }
        }

        cache = apps
        lastRefresh = Date()
    }
}
