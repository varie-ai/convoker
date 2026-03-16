import SwiftUI

// MARK: - Palette Item (unified result type)

/// A single item in the palette results — either an app or a workspace.
enum PaletteItem: Identifiable, Equatable {
    case app(AppInfo)
    case workspace(Workspace)

    var id: String {
        switch self {
        case .app(let app): return "app:\(app.id)"
        case .workspace(let ws): return "ws:\(ws.id.uuidString)"
        }
    }

    var isApp: Bool {
        if case .app = self { return true }
        return false
    }
}

// MARK: - View Model

/// View model for the command palette — owns the search state and app list.
@MainActor
class CommandPaletteViewModel: ObservableObject {
    enum PaletteMode: Equatable {
        case normal
        case pinned(apps: [AppInfo])  // 1-3 pinned apps
        case saving                   // Workspace save: type a name
    }

    @Published var searchText = ""
    @Published var selectedIndex: Int? = nil
    @Published var filteredItems: [PaletteItem] = []
    @Published var mode: PaletteMode = .normal

    // Legacy accessor for filtered apps only (used by pin/split logic)
    var filteredApps: [AppInfo] {
        filteredItems.compactMap {
            if case .app(let app) = $0 { return app }
            return nil
        }
    }

    private let appResolver = AppResolver()

    var pinnedApps: [AppInfo] {
        if case .pinned(let apps) = mode { return apps }
        return []
    }

    var isPinned: Bool { !pinnedApps.isEmpty }
    var isSaving: Bool { mode == .saving }

    init() {
        refreshApps()
    }

    func reset() {
        searchText = ""
        selectedIndex = nil
        mode = .normal
        refreshApps()
    }

    func refreshApps() {
        appResolver.refresh()
        updateFiltered()
    }

    func updateFiltered() {
        // In save mode, don't update results — the text field is the workspace name
        if isSaving { return }

        var items: [PaletteItem] = []

        // Apps
        var apps: [AppInfo]
        if searchText.isEmpty {
            apps = appResolver.allApps()
        } else {
            apps = appResolver.search(query: searchText)
        }
        // In pinned mode, exclude all pinned apps from results
        if !pinnedApps.isEmpty {
            let pinnedIDs = Set(pinnedApps.map(\.id))
            apps = apps.filter { !pinnedIDs.contains($0.id) }
        }

        // Workspaces (only in normal mode, not pinned — pinned is building a split)
        var workspaceItems: [PaletteItem] = []
        if case .normal = mode {
            let workspaces = WorkspaceStore.shared.search(query: searchText)
            let sorted = workspaces.sorted { a, b in
                let aUsage = UsageTracker.count(for: "workspace:\(a.id.uuidString)")
                let bUsage = UsageTracker.count(for: "workspace:\(b.id.uuidString)")
                if aUsage != bUsage { return aUsage > bUsage }
                return a.updatedAt > b.updatedAt
            }
            workspaceItems = sorted.map { .workspace($0) }
        }

        if searchText.isEmpty {
            // Browsing: running apps first, then workspaces at bottom
            items.append(contentsOf: apps.map { .app($0) })
            items.append(contentsOf: workspaceItems)
        } else {
            // Searching: workspaces first (they're named, intentional targets),
            // then apps. This ensures an exact-match workspace ranks above
            // fuzzy-matched launchable apps.
            items.append(contentsOf: workspaceItems)
            items.append(contentsOf: apps.map { .app($0) })
        }

        filteredItems = items

        if searchText.count >= 2 {
            NotificationCenter.default.post(name: .convokerSearchDidType, object: nil)
        }

        // Auto-select top match only when user has typed something
        if !searchText.isEmpty && !filteredItems.isEmpty {
            selectedIndex = 0
        } else if searchText.isEmpty {
            selectedIndex = nil
        }
        // Clamp selection if it overflows
        if let idx = selectedIndex, idx >= filteredItems.count {
            selectedIndex = filteredItems.isEmpty ? nil : filteredItems.count - 1
        }
    }

    func moveSelection(by delta: Int) {
        guard !filteredItems.isEmpty else { return }
        guard let current = selectedIndex else {
            selectedIndex = delta > 0 ? 0 : filteredItems.count - 1
            return
        }
        selectedIndex = (current + delta + filteredItems.count) % filteredItems.count
    }

    // MARK: - Actions

    func gatherSelected(maximize: Bool = false) {
        guard let idx = selectedIndex, idx < filteredItems.count else { return }
        guard case .app(let app) = filteredItems[idx] else { return }
        UsageTracker.recordAction(bundleID: app.bundleID)
        PanelManager.shared.hide()
        NotificationCenter.default.post(name: .convokerDidGather, object: nil)
        Task {
            if app.isRunning {
                await WindowGatherer.gather(app: app, maximize: maximize)
            } else {
                await WindowGatherer.launchAndGather(app: app, maximize: maximize)
            }
        }
    }

    func focusSelected() {
        guard let idx = selectedIndex, idx < filteredItems.count else { return }
        guard case .app(let app) = filteredItems[idx] else { return }
        UsageTracker.recordAction(bundleID: app.bundleID)
        PanelManager.shared.hide()
        NotificationCenter.default.post(name: .convokerDidFocus, object: nil)
        Task {
            await WindowGatherer.focus(app: app)
        }
    }

    func recallWorkspace(_ workspace: Workspace) {
        UsageTracker.recordAction(bundleID: "workspace:\(workspace.id.uuidString)")
        PanelManager.shared.hide()
        Task {
            await WindowGatherer.recallWorkspace(workspace)
        }
    }

    func pinSelected() {
        guard let idx = selectedIndex, idx < filteredItems.count else { return }
        guard case .app(let app) = filteredItems[idx] else { return }
        var current = pinnedApps
        guard current.count < 3 else { return }
        current.append(app)
        mode = .pinned(apps: current)
        searchText = ""
        selectedIndex = nil
        updateFiltered()
        NotificationCenter.default.post(name: .convokerDidPinForSplit, object: nil)
    }

    func unpin() {
        var current = pinnedApps
        current.removeLast()
        if current.isEmpty {
            mode = .normal
        } else {
            mode = .pinned(apps: current)
        }
        searchText = ""
        selectedIndex = nil
        updateFiltered()
    }

    func splitSelected(rightSide: Bool = false) {
        guard !pinnedApps.isEmpty else { return }
        var allApps = pinnedApps
        if let idx = selectedIndex, idx < filteredItems.count,
           case .app(let app) = filteredItems[idx] {
            allApps.append(app)
        }
        for app in allApps {
            UsageTracker.recordAction(bundleID: app.bundleID)
        }
        PanelManager.shared.hide()
        NotificationCenter.default.post(name: .convokerDidSplit, object: nil)
        Task {
            await WindowGatherer.split(apps: allApps, rightSide: rightSide)
        }
    }

    // MARK: - Workspace Save

    /// Enter save mode — user types a workspace name.
    func enterSaveMode() {
        mode = .saving
        searchText = ""
        selectedIndex = nil
        filteredItems = []
    }

    /// Save current desktop state as a workspace with the given name.
    func confirmSave() {
        let name = searchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let assignments = WindowGatherer.inferCurrentLayout()
        _ = WorkspaceStore.shared.saveOrOverwrite(name: name, assignments: assignments)
        PanelManager.shared.hide()
        NotificationCenter.default.post(name: .convokerDidSaveWorkspace, object: nil)
    }

    /// Save pinned apps as a workspace (Cmd+Shift+S from pin mode).
    func saveFromPins() {
        guard !pinnedApps.isEmpty else { return }
        // Switch to save mode — user needs to type a name
        let apps = pinnedApps
        mode = .saving
        searchText = ""
        selectedIndex = nil
        filteredItems = []
        // Store pinned apps temporarily so confirmSaveFromPins can use them
        _pendingSavePins = apps
    }

    private var _pendingSavePins: [AppInfo]?

    /// Confirm save from pins with the typed name.
    func confirmSaveFromPins() {
        let name = searchText.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard let apps = _pendingSavePins, !apps.isEmpty else {
            // No pins — fall back to save current state
            confirmSave()
            return
        }
        PanelManager.shared.hide()

        // Build assignments from pinned apps using split regions
        let regions = Region.splitRegions(count: apps.count)
        var assignments: [AppAssignment] = []
        for (i, app) in apps.enumerated() where i < regions.count {
            assignments.append(AppAssignment(
                bundleID: app.bundleID ?? app.id,
                appName: app.name,
                screen: .cursor,
                region: regions[i]
            ))
        }
        _ = WorkspaceStore.shared.saveOrOverwrite(name: name, assignments: assignments)
        _pendingSavePins = nil
    }

    /// Dispatch Enter/Shift+Enter/Alt+Enter based on current mode.
    func executeAction(maximize: Bool = false, rightSide: Bool = false) {
        switch mode {
        case .normal:
            guard let idx = selectedIndex, idx < filteredItems.count else { return }
            switch filteredItems[idx] {
            case .app:
                gatherSelected(maximize: maximize)
            case .workspace(let ws):
                recallWorkspace(ws)
            }
        case .pinned:
            splitSelected(rightSide: rightSide)
        case .saving:
            if _pendingSavePins != nil {
                confirmSaveFromPins()
            } else {
                confirmSave()
            }
        }
    }

    /// Check if the search text is the "save" keyword.
    var isSaveKeyword: Bool {
        searchText.trimmingCharacters(in: .whitespaces).lowercased() == "save"
    }
}

// MARK: - Command Palette View

/// The command palette UI — search field + scrollable app list.
struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pinned apps indicator (split mode)
            if viewModel.isPinned {
                pinnedBar
                Divider()
            }

            // Save mode header
            if viewModel.isSaving {
                saveHeader
                Divider()
            }

            // Search field with shortcut hints as background watermark
            ZStack(alignment: .trailing) {
                ShortcutHintsInline(
                    isPinned: viewModel.isPinned,
                    pinCount: viewModel.pinnedApps.count,
                    hasSelection: viewModel.selectedIndex != nil,
                    isSaving: viewModel.isSaving
                )
                .padding(.trailing, 16)

                HStack(spacing: 10) {
                    Image(systemName: viewModel.isSaving ? "square.and.arrow.down" : "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))

                    TextField(
                        viewModel.isSaving ? "Workspace name..." :
                            viewModel.isPinned ? "App \(viewModel.pinnedApps.count + 1)..." : "App name...",
                        text: $viewModel.searchText
                    )
                        .textFieldStyle(.plain)
                        .font(.system(size: 18))
                        .focused($isSearchFocused)
                        .onChange(of: viewModel.searchText) {
                            viewModel.updateFiltered()
                        }
                }
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 12)

            Divider()

            // Results list (apps + workspaces) — hidden in save mode
            if !viewModel.isSaving {
                resultsList
            }

            // "Save" action row when keyword matches
            if viewModel.isSaveKeyword && !viewModel.isSaving {
                Divider()
                saveActionRow
            }
        }
        .background(VisualEffectView())
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
        .onAppear {
            isSearchFocused = true
        }
        .onKeyPress(.upArrow) {
            viewModel.moveSelection(by: -1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            viewModel.moveSelection(by: 1)
            return .handled
        }
        .onKeyPress(.escape) {
            if viewModel.isSaving {
                viewModel.mode = .normal
                viewModel.searchText = ""
                viewModel.updateFiltered()
            } else if viewModel.isPinned {
                viewModel.unpin()
            } else {
                PanelManager.shared.hide()
            }
            return .handled
        }
        // Tab and Cmd+Enter are handled by NSEvent monitor in PanelManager
        // (SwiftUI TextField intercepts Tab before .onKeyPress fires)
        // Option+Return and Cmd+Return are handled by NSEvent monitor in PanelManager
        // (TextField intercepts Option+Return as context menu before .onKeyPress fires)
        .onKeyPress(keys: [.return]) { keyPress in
            // "save" keyword → enter save mode
            if viewModel.isSaveKeyword && !viewModel.isSaving {
                viewModel.enterSaveMode()
                return .handled
            }
            if keyPress.modifiers.contains(.shift) {
                viewModel.executeAction(maximize: true)
            } else {
                viewModel.executeAction()
            }
            return .handled
        }
    }

    // MARK: - Subviews

    private var pinnedBar: some View {
        HStack(spacing: 8) {
            ForEach(Array(viewModel.pinnedApps.enumerated()), id: \.element.id) { index, app in
                if index > 0 {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if let icon = app.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("\(index + 1)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
            }
            Spacer()
            if viewModel.pinnedApps.count >= 3 {
                Text("Esc to undo")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Tab to add · Esc to undo")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.05))
    }

    private var saveHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            Text("Save Workspace")
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text("Enter to save · Esc to cancel")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.05))
    }

    private var resultsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.filteredItems.enumerated()), id: \.element.id) { index, item in
                        Group {
                            switch item {
                            case .app(let app):
                                AppRow(
                                    app: app,
                                    isSelected: viewModel.selectedIndex == index,
                                    splitPosition: viewModel.isPinned ? viewModel.pinnedApps.count + 1 : 0
                                )
                            case .workspace(let ws):
                                WorkspaceRow(
                                    workspace: ws,
                                    isSelected: viewModel.selectedIndex == index
                                )
                            }
                        }
                        .id(index)
                        .onTapGesture {
                            viewModel.selectedIndex = index
                            viewModel.executeAction()
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .onChange(of: viewModel.selectedIndex) { _, newValue in
                if let idx = newValue {
                    withAnimation(.easeOut(duration: 0.1)) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    private var saveActionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .resizable()
                .frame(width: 24, height: 24)
                .foregroundStyle(.green)

            Text("Save current layout as workspace")
                .font(.system(size: 14))

            Spacer()

            Text("Enter")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.05))
    }
}

// MARK: - Row Views

/// A single app row in the results list.
struct AppRow: View {
    let app: AppInfo
    let isSelected: Bool
    var splitPosition: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            if let icon = app.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
                    .opacity(app.isRunning ? 1.0 : 0.5)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.secondary)
            }

            Text(app.name)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()

            if splitPosition > 0 && isSelected {
                Text("\(splitPosition)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .cornerRadius(4)
            }

            if app.isRunning {
                Text("\(app.windowCount) window\(app.windowCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Launch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

/// A workspace row in the results list — distinct from app rows.
struct WorkspaceRow: View {
    let workspace: Workspace
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.3.group")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .foregroundStyle(.green)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(workspace.appSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text("\(workspace.appCount) apps")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .contentShape(Rectangle())
    }
}

// MARK: - Shortcut Hints

/// Inline shortcut hints shown right-aligned in the search bar.
struct ShortcutHintsInline: View {
    let isPinned: Bool
    var pinCount: Int = 0
    var hasSelection: Bool = false
    var isSaving: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isSaving {
                hint("ESC", "Cancel")
                hint("⏎", "Save")
            } else if isPinned {
                hint("ESC", "Undo")
                if hasSelection {
                    hint("⏎", "Split \(pinCount + 1)")
                } else if pinCount == 1 {
                    hint("⏎", "Left")
                    hint("⌥⏎", "Right")
                } else {
                    hint("⏎", "Split \(pinCount)")
                }
                if pinCount < 3 {
                    hint("TAB", "Add")
                }
            } else {
                hint("⏎", "Gather")
                hint("⇧⏎", "Max")
                hint("⌘⏎", "Focus")
                hint("TAB", "Split")
                hint("⌘⇧S", "Save Workspace")
            }
        }
        .fixedSize()
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 3) {
            Text(key)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.1))
                .cornerRadius(4)
            Text(label)
                .font(.system(size: 14))
        }
        .foregroundStyle(.tertiary)
    }
}

// MARK: - Visual Effect

/// NSVisualEffectView wrapper for vibrancy background.
struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
