import Foundation

// MARK: - Screen Target

/// Which screen an app should be placed on.
enum ScreenTarget: String, Codable, Equatable, Hashable {
    case primary    // Main display
    case secondary  // Second display
    case tertiary   // Third display
    case cursor     // Wherever cursor is (single-screen fallback)
}

// MARK: - App Assignment

/// A single app's placement in a workspace recipe.
/// An app can have multiple assignments (one per screen) when its windows
/// span multiple displays.
struct AppAssignment: Codable, Equatable, Identifiable {
    /// Unique within a workspace. Composite of bundleID + screen for multi-screen apps.
    var id: String { "\(bundleID)@\(screen.rawValue)" }
    let bundleID: String
    let appName: String
    let screen: ScreenTarget
    let region: Region
    var launchIfNeeded: Bool = true
    /// Front-to-back stacking order (0 = frontmost). Used during recall to
    /// restore the same z-ordering the user had when saving.
    var zOrder: Int = 0
    /// Number of windows on this screen at save time. Used to restore window count.
    var windowCount: Int = 0
}

// MARK: - Workspace

/// A named workspace recipe — describes intent, not pixel positions.
struct Workspace: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var assignments: [AppAssignment]
    var hideOthers: Bool
    let createdAt: Date
    var updatedAt: Date

    init(name: String, assignments: [AppAssignment], hideOthers: Bool = true) {
        self.id = UUID()
        self.name = name
        self.assignments = assignments
        self.hideOthers = hideOthers
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Short subtitle listing unique app names (e.g., "Xcode + Terminal + Safari").
    var appSummary: String {
        var seen = Set<String>()
        var names: [String] = []
        for a in assignments {
            if seen.insert(a.bundleID).inserted {
                names.append(a.appName)
            }
        }
        return names.joined(separator: " + ")
    }

    /// Number of unique apps in this workspace.
    var appCount: Int {
        Set(assignments.map(\.bundleID)).count
    }
}

// MARK: - Workspace Store

/// Persists workspaces as JSON in the app support directory.
class WorkspaceStore: ObservableObject {
    static let shared = WorkspaceStore()

    @Published private(set) var workspaces: [Workspace] = []

    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = appSupport.appendingPathComponent("Convoker", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("workspaces.json")
        }
        load()
    }

    // MARK: - CRUD

    func save(_ workspace: Workspace) {
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspace
        } else {
            workspaces.append(workspace)
        }
        persist()
    }

    func saveOrOverwrite(name: String, assignments: [AppAssignment], hideOthers: Bool = true) -> Workspace {
        if let index = workspaces.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            workspaces[index].assignments = assignments
            workspaces[index].hideOthers = hideOthers
            workspaces[index].updatedAt = Date()
            persist()
            return workspaces[index]
        } else {
            let workspace = Workspace(name: name, assignments: assignments, hideOthers: hideOthers)
            workspaces.append(workspace)
            persist()
            return workspace
        }
    }

    func delete(_ workspace: Workspace) {
        workspaces.removeAll { $0.id == workspace.id }
        persist()
    }

    func delete(at offsets: IndexSet) {
        workspaces.remove(atOffsets: offsets)
        persist()
    }

    func workspace(named name: String) -> Workspace? {
        workspaces.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Search workspaces by name (simple contains match — fuse is overkill for <50 items).
    func search(query: String) -> [Workspace] {
        guard !query.isEmpty else { return workspaces }
        let q = query.lowercased()
        return workspaces.filter { $0.name.lowercased().contains(q) }
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            workspaces = try JSONDecoder().decode([Workspace].self, from: data)
        } catch {
            // Corrupted file — start fresh
            workspaces = []
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(workspaces)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Silent fail — workspace save is best-effort
        }
    }
}
