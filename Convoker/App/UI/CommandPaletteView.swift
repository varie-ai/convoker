import SwiftUI

/// View model for the command palette — owns the search state and app list.
@MainActor
class CommandPaletteViewModel: ObservableObject {
    enum PaletteMode: Equatable {
        case normal
        case pinned(apps: [AppInfo])  // 1-3 pinned apps
    }

    @Published var searchText = ""
    @Published var selectedIndex: Int? = nil
    @Published var filteredApps: [AppInfo] = []
    @Published var mode: PaletteMode = .normal

    private let appResolver = AppResolver()

    var pinnedApps: [AppInfo] {
        if case .pinned(let apps) = mode { return apps }
        return []
    }

    var isPinned: Bool { !pinnedApps.isEmpty }

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
        if searchText.isEmpty {
            filteredApps = appResolver.allApps()
        } else {
            filteredApps = appResolver.search(query: searchText)
        }
        // In pinned mode, exclude all pinned apps from results
        if !pinnedApps.isEmpty {
            let pinnedIDs = Set(pinnedApps.map(\.id))
            filteredApps = filteredApps.filter { !pinnedIDs.contains($0.id) }
        }
        // Auto-select top match only when user has typed something
        if !searchText.isEmpty && !filteredApps.isEmpty {
            selectedIndex = 0
        } else if searchText.isEmpty {
            selectedIndex = nil
        }
        // Clamp selection if it overflows
        if let idx = selectedIndex, idx >= filteredApps.count {
            selectedIndex = filteredApps.isEmpty ? nil : filteredApps.count - 1
        }
    }

    func moveSelection(by delta: Int) {
        guard !filteredApps.isEmpty else { return }
        guard let current = selectedIndex else {
            // First arrow press: down → first item, up → last item
            selectedIndex = delta > 0 ? 0 : filteredApps.count - 1
            return
        }
        selectedIndex = (current + delta + filteredApps.count) % filteredApps.count
    }

    // MARK: - Actions

    func gatherSelected(maximize: Bool = false) {
        guard let idx = selectedIndex, idx < filteredApps.count else { return }
        let app = filteredApps[idx]
        UsageTracker.recordAction(bundleID: app.bundleID)
        PanelManager.shared.hide()
        Task {
            if app.isRunning {
                await WindowGatherer.gather(app: app, maximize: maximize)
            } else {
                await WindowGatherer.launchAndGather(app: app, maximize: maximize)
            }
        }
    }

    func focusSelected() {
        guard let idx = selectedIndex, idx < filteredApps.count else { return }
        let app = filteredApps[idx]
        UsageTracker.recordAction(bundleID: app.bundleID)
        PanelManager.shared.hide()
        Task {
            await WindowGatherer.focus(app: app)
        }
    }

    func pinSelected() {
        guard let idx = selectedIndex, idx < filteredApps.count else { return }
        let app = filteredApps[idx]
        var current = pinnedApps
        guard current.count < 3 else { return }  // Max 3 pins
        current.append(app)
        mode = .pinned(apps: current)
        searchText = ""
        selectedIndex = nil
        updateFiltered()
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
        // If a selection exists, include it; otherwise confirm pinned-only
        var allApps = pinnedApps
        if let idx = selectedIndex, idx < filteredApps.count {
            allApps.append(filteredApps[idx])
        }
        for app in allApps {
            UsageTracker.recordAction(bundleID: app.bundleID)
        }
        PanelManager.shared.hide()
        Task {
            await WindowGatherer.split(apps: allApps, rightSide: rightSide)
        }
    }

    /// Dispatch Enter/Shift+Enter/Alt+Enter based on current mode.
    func executeAction(maximize: Bool = false, rightSide: Bool = false) {
        switch mode {
        case .normal:
            // No selection = no-op (explicit selection required)
            guard selectedIndex != nil else { return }
            gatherSelected(maximize: maximize)
        case .pinned(_):
            // Always allowed: confirms pinned-only or pinned+selected
            splitSelected(rightSide: rightSide)
        }
    }
}

/// The command palette UI — search field + scrollable app list.
struct CommandPaletteView: View {
    @ObservedObject var viewModel: CommandPaletteViewModel
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Pinned apps indicator (split mode)
            if viewModel.isPinned {
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

                Divider()
            }

            // Search field with shortcut hints as background watermark
            ZStack(alignment: .trailing) {
                // Hints sit behind the text field — visible when text is short,
                // naturally hidden as text expands over them
                ShortcutHintsInline(isPinned: viewModel.isPinned, pinCount: viewModel.pinnedApps.count, hasSelection: viewModel.selectedIndex != nil)
                    .padding(.trailing, 16)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 16))

                    TextField(
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

            // App list
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.filteredApps.enumerated()), id: \.element.id) { index, app in
                            AppRow(
                                app: app,
                                isSelected: viewModel.selectedIndex == index,
                                splitPosition: viewModel.isPinned ? viewModel.pinnedApps.count + 1 : 0
                            )
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
            if viewModel.isPinned {
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
            if keyPress.modifiers.contains(.shift) {
                viewModel.executeAction(maximize: true)
            } else {
                viewModel.executeAction()
            }
            return .handled
        }
    }
}

/// A single app row in the results list.
struct AppRow: View {
    let app: AppInfo
    let isSelected: Bool
    var splitPosition: Int = 0  // 0 = not in split mode, 2-4 = position number

    var body: some View {
        HStack(spacing: 12) {
            // App icon (dimmed for non-running)
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

            // App name
            Text(app.name)
                .font(.system(size: 14))
                .lineLimit(1)

            Spacer()

            // Position badge on selected row in split mode
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
                // Window count
                Text("\(app.windowCount) window\(app.windowCount == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                // Launch badge
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

/// Inline shortcut hints shown right-aligned in the search bar.
struct ShortcutHintsInline: View {
    let isPinned: Bool
    var pinCount: Int = 0
    var hasSelection: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if isPinned {
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
                hint("ESC", "Close")
                hint("⏎", "Gather")
                hint("⇧⏎", "Max")
                hint("⌘⏎", "Focus")
                hint("TAB", "Split")
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
