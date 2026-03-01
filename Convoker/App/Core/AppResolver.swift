import AppKit
import Fuse

/// Metadata for a running or installed app.
struct AppInfo: Identifiable, Equatable {
    let id: String  // bundleIdentifier or PID string
    let name: String
    let bundleID: String?
    let pid: pid_t?         // nil for non-running apps
    let icon: NSImage?
    var windowCount: Int
    let bundleURL: URL?     // for launching non-running apps

    var isRunning: Bool { pid != nil }
}

/// Discovers running GUI apps and provides fuzzy search.
@MainActor
class AppResolver {
    private var apps: [AppInfo] = []
    private let fuse = Fuse(threshold: 0.6, isCaseSensitive: false)
    private var observers: [NSObjectProtocol] = []

    init() {
        refresh()
        observeWorkspace()
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    /// Refresh the list of running GUI apps.
    func refresh() {
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        apps = running.map { app in
            let pid = app.processIdentifier
            let windowCount = Self.countWindows(pid: pid)
            return AppInfo(
                id: app.bundleIdentifier ?? "\(pid)",
                name: app.localizedName ?? "Unknown",
                bundleID: app.bundleIdentifier,
                pid: pid,
                icon: app.icon,
                windowCount: windowCount,
                bundleURL: app.bundleURL
            )
        }
        // Sort: usage count (desc) → window count (desc) → alphabetical
        apps.sort { a, b in
            let aUsage = UsageTracker.count(for: a.bundleID)
            let bUsage = UsageTracker.count(for: b.bundleID)
            if aUsage != bUsage { return aUsage > bUsage }
            if a.windowCount != b.windowCount { return a.windowCount > b.windowCount }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// All apps (unfiltered), sorted by window count.
    func allApps() -> [AppInfo] {
        return apps
    }

    /// Fuzzy search for apps matching query. Includes installed (non-running) apps.
    func search(query: String) -> [AppInfo] {
        // Merge running apps with installed-but-not-running apps
        let runningIDs = Set(apps.compactMap(\.bundleID))
        let installed: [AppInfo] = AppCatalog.shared.allInstalledApps()
            .filter { !runningIDs.contains($0.bundleID) }
            .map { app in
                AppInfo(
                    id: app.bundleID,
                    name: app.name,
                    bundleID: app.bundleID,
                    pid: nil,
                    icon: app.icon,
                    windowCount: 0,
                    bundleURL: app.bundleURL
                )
            }
        let all = apps + installed

        let names = all.map(\.name)
        let results = fuse.search(query, in: names)
        return results
            .sorted { a, b in
                // At similar scores, prefer running apps
                if abs(a.score - b.score) < 0.1 {
                    let aRunning = all[a.index].isRunning
                    let bRunning = all[b.index].isRunning
                    if aRunning != bRunning { return aRunning }
                }
                return a.score < b.score
            }
            .compactMap { result in
                guard result.index < all.count else { return nil }
                return all[result.index]
            }
    }

    // MARK: - Private

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            observers.append(observer)
        }
    }

    /// Count windows using AXUIElement (accurate for user-visible windows).
    /// Note: may miss windows on other Spaces, but avoids
    /// overcounting internal windows (tabs, helpers) that CGWindowList reports.
    private static func countWindows(pid: pid_t) -> Int {
        let appElement = AccessibilityElement.from(pid: pid)
        appElement.setTimeout(0.3)
        let windows = appElement.getWindows()
        return windows.filter { $0.isGatherableWindow || $0.isMinimized }.count
    }
}
