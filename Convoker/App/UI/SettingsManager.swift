import AppKit
import SwiftUI

/// Manages the settings window lifecycle.
@MainActor
class SettingsManager {
    static let shared = SettingsManager()

    private var window: NSWindow?

    private init() {}

    func create() {
        let contentView = SettingsView()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Convoker Settings"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false

        self.window = window
    }

    func show() {
        guard let window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
