import SwiftUI

@main
struct ConvokerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let _ = initializeDelegateIfNeeded()

        MenuBarExtra {
            VStack(spacing: 8) {
                Button("Show Panel") {
                    PanelManager.shared.toggle()
                }

                Button("Settings...") {
                    SettingsManager.shared.show()
                }
                .keyboardShortcut(",")

                Divider()

                Button("Quit Convoker") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding(4)
        } label: {
            Image(systemName: "rectangle.3.group")
        }
    }

    private func initializeDelegateIfNeeded() {
        if !appDelegate.isInitialized {
            appDelegate.initialize()
        }
    }
}
