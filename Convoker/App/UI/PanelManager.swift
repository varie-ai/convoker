import AppKit
import SwiftUI

/// Manages the floating command palette panel lifecycle.
@MainActor
class PanelManager {
    static let shared = PanelManager()

    private var panel: FloatingPanel?
    var viewModel: CommandPaletteViewModel?
    private var eventMonitor: Any?

    private init() {}

    func create() {
        let vm = CommandPaletteViewModel()
        self.viewModel = vm

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 400)
        )

        let contentView = CommandPaletteView(viewModel: vm)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = []
        panel.contentView = hostingView

        self.panel = panel
    }

    func toggle() {
        guard let panel else { return }
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let panel else { return }

        // Position at center-top of the active screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let panelSize = panel.frame.size
            let x = screenFrame.midX - panelSize.width / 2
            let y = screenFrame.maxY - panelSize.height - 80 // Upper third
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        // Reset state
        viewModel?.reset()

        panel.orderFront(nil)
        panel.makeKey()
        installKeyMonitor()
    }

    func hide() {
        panel?.orderOut(nil)
        removeKeyMonitor()
    }

    // MARK: - Key Monitor

    /// Intercept Tab and Cmd+Enter at AppKit level before SwiftUI's TextField eats them.
    private func installKeyMonitor() {
        removeKeyMonitor()
        let vm = self.viewModel
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let vm else { return event }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Tab key (keyCode 48), no modifiers
            if event.keyCode == 48, flags.isEmpty {
                Task { @MainActor in
                    // Tab requires a selection to pin
                    guard vm.selectedIndex != nil else { return }
                    if vm.pinnedApps.count < 3 {
                        vm.pinSelected()
                    }
                }
                return nil // consume
            }

            // Cmd+Return (keyCode 36)
            if event.keyCode == 36, flags == .command {
                Task { @MainActor in
                    vm.focusSelected()
                }
                return nil
            }

            // Option+Return (keyCode 36) — gather right in 1-pin mode
            if event.keyCode == 36, flags == .option {
                Task { @MainActor in
                    vm.executeAction(rightSide: true)
                }
                return nil
            }

            // Cmd+Shift+S (keyCode 1) — save workspace from pins
            if event.keyCode == 1, flags == [.command, .shift] {
                Task { @MainActor in
                    if vm.isPinned {
                        vm.saveFromPins()
                    } else {
                        vm.enterSaveMode()
                    }
                }
                return nil
            }

            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
}
