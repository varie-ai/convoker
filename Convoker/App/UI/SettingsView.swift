import SwiftUI
import KeyboardShortcuts
import ServiceManagement

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("gatherLayout") private var gatherLayout = GatherLayout.grid.rawValue
    @AppStorage("splitRatio") private var splitRatio = SplitRatio.equal.rawValue

    var body: some View {
        Form {
            Section("General") {
                KeyboardShortcuts.Recorder("Show Panel:", name: .showPanel)

                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        do {
                            if newValue {
                                try SMAppService.mainApp.register()
                            } else {
                                try SMAppService.mainApp.unregister()
                            }
                        } catch {
                            // Revert toggle on failure
                            launchAtLogin = !newValue
                        }
                    }
            }

            Section("Layout") {
                Picker("Gather Layout:", selection: $gatherLayout) {
                    Text("Grid").tag(GatherLayout.grid.rawValue)
                    Text("Cascade").tag(GatherLayout.cascade.rawValue)
                    Text("Side by Side").tag(GatherLayout.sideBySide.rawValue)
                }

                Picker("Split Ratio (1-app and 2-app):", selection: $splitRatio) {
                    Text("50 / 50").tag(SplitRatio.equal.rawValue)
                    Text("60 / 40").tag(SplitRatio.sixtyForty.rawValue)
                    Text("70 / 30").tag(SplitRatio.seventyThirty.rawValue)
                }
            }

            Section("Workspaces") {
                if WorkspaceStore.shared.workspaces.isEmpty {
                    Text("No saved workspaces")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 13))
                } else {
                    ForEach(WorkspaceStore.shared.workspaces) { workspace in
                        WorkspaceSettingsRow(workspace: workspace)
                    }
                }
            }

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}

/// A single workspace row in the settings panel.
struct WorkspaceSettingsRow: View {
    let workspace: Workspace
    @State private var hideOthers: Bool

    init(workspace: Workspace) {
        self.workspace = workspace
        _hideOthers = State(initialValue: workspace.hideOthers)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(workspace.name)
                    .font(.system(size: 13, weight: .medium))
                Text(workspace.appSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("Hide others", isOn: $hideOthers)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .onChange(of: hideOthers) { _, newValue in
                    var updated = workspace
                    updated.hideOthers = newValue
                    WorkspaceStore.shared.save(updated)
                }

            Button(role: .destructive) {
                WorkspaceStore.shared.delete(workspace)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
    }
}
