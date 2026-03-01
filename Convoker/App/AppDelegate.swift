import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let showPanel = Self("showPanel", default: .init(.x, modifiers: [.command, .shift]))
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var isInitialized = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialization happens via initialize() called from SwiftUI body
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func initialize() {
        guard !isInitialized else { return }
        isInitialized = true

        if AXIsProcessTrusted() {
            setupApp()
        } else {
            // AXIsProcessTrusted() can briefly return false at launch even when granted.
            // Retry a few times before showing the permission prompt.
            retryAccessibilityCheck(attemptsRemaining: 3)
        }
    }

    private func retryAccessibilityCheck(attemptsRemaining: Int) {
        guard attemptsRemaining > 0 else {
            promptForAccessibility()
            return
        }
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            Task { @MainActor in
                if AXIsProcessTrusted() {
                    self?.setupApp()
                } else {
                    self?.retryAccessibilityCheck(attemptsRemaining: attemptsRemaining - 1)
                }
            }
        }
    }

    private func setupApp() {
        // Create the command palette panel and settings window
        PanelManager.shared.create()
        SettingsManager.shared.create()

        // Register global hotkey
        KeyboardShortcuts.onKeyUp(for: .showPanel) {
            PanelManager.shared.toggle()
        }
    }

    private func promptForAccessibility() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Convoker needs accessibility access to discover and move windows.\n\nClick \"Open System Settings\" to grant permission, then relaunch the app."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            // Open Accessibility pane directly
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)

            // Also trigger the system prompt (creates the entry in the list)
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }

        // Poll for permission grant
        pollForAccessibility()
    }

    private func pollForAccessibility() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                Task { @MainActor in
                    self?.setupApp()
                }
            }
        }
    }
}
