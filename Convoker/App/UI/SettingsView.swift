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

            Section("About") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.3")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize()
    }
}
