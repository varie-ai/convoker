import AppKit

/// Orchestrates window operations: gather, focus, split.
enum WindowGatherer {
    /// Focus mode: activate the given app and hide all other regular apps.
    /// Does NOT move or rearrange any windows — just clears the noise.
    static func focus(app: AppInfo) async {
        guard let pid = app.pid else {
            await launchApp(app: app)
            return
        }
        await MainActor.run {
            let running = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
            for other in running where other.processIdentifier != pid {
                other.hide()
            }
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
    }

    /// Launch a non-running app (activate only, no window manipulation).
    static func launchApp(app: AppInfo) async {
        guard let bundleURL = app.bundleURL else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
    }

    /// Launch a non-running app, wait for its first window, then gather.
    static func launchAndGather(app: AppInfo, maximize: Bool = false) async {
        guard let bundleURL = app.bundleURL else { return }
        let targetFrame = await MainActor.run { Self.cursorScreenFrame() }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        guard let runningApp = try? await NSWorkspace.shared.openApplication(
            at: bundleURL, configuration: config
        ) else { return }

        let pid = runningApp.processIdentifier
        // Poll for first window (up to 15s — covers slow apps)
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let appElement = AccessibilityElement.from(pid: pid)
            appElement.setTimeout(0.3)
            let windows = appElement.getWindows().filter { $0.isGatherableWindow }
            if !windows.isEmpty {
                let launchedApp = AppInfo(
                    id: app.id, name: app.name, bundleID: app.bundleID,
                    pid: pid, icon: app.icon, windowCount: windows.count,
                    bundleURL: app.bundleURL
                )
                await gather(app: launchedApp, maximize: maximize)
                return
            }
        }
        // Timeout — app launched but no window yet; at least it's active
    }

    /// Gather all windows of the given app onto the cursor's screen.
    /// - Parameters:
    ///   - app: The target app
    ///   - maximize: If true, single windows fill the screen. If false, single windows keep their size.
    static func gather(app: AppInfo, maximize: Bool = false) async {
        // Capture cursor screen NOW on the main thread, before async work
        let targetFrame = await MainActor.run { Self.cursorScreenFrame() }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                performGather(app: app, maximize: maximize, targetFrame: targetFrame)
                continuation.resume()
            }
        }
    }

    /// Split 1-4 apps on the cursor's screen.
    /// Running apps are laid out immediately. Non-running apps are launched in the
    /// background and placed into their reserved region when their windows appear.
    static func split(apps: [AppInfo], rightSide: Bool = false) async {
        let targetFrame = await MainActor.run { Self.cursorScreenFrame() }
        let regions = LayoutEngine.splitLayout(appCount: apps.count, in: targetFrame, gap: 0, rightSide: rightSide)
        guard regions.count == apps.count else { return }

        // Fire off launches for non-running apps (don't await — completely non-blocking)
        var launchTasks: [(Int, Task<pid_t?, Never>)] = []
        for (i, app) in apps.enumerated() where !app.isRunning {
            guard let bundleURL = app.bundleURL else { continue }
            let task = Task<pid_t?, Never> {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                if let runningApp = try? await NSWorkspace.shared.openApplication(
                    at: bundleURL, configuration: config
                ) {
                    return runningApp.processIdentifier
                }
                return nil
            }
            launchTasks.append((i, task))
        }

        // Layout running apps IMMEDIATELY (no waiting for launches)
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                performSplit(apps: apps, targetFrame: targetFrame, rightSide: rightSide)
                continuation.resume()
            }
        }

        // Background: await each launch, then monitor and place when windows appear
        for (index, launchTask) in launchTasks {
            Task {
                guard let pid = await launchTask.value else { return }
                await monitorAndPlace(pid: pid, region: regions[index])
            }
        }
    }

    /// Poll for a launched app's windows and place them into the reserved region.
    /// Polls every 500ms for up to 30s — covers slow-launching apps.
    private static func monitorAndPlace(pid: pid_t, region: CGRect) async {
        for _ in 0..<60 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let appElement = AccessibilityElement.from(pid: pid)
            appElement.setTimeout(0.5)
            let windows = appElement.getWindows().filter { $0.isGatherableWindow }
            if !windows.isEmpty {
                await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        activateApp(pid: pid)
                        Thread.sleep(forTimeInterval: 0.5)
                        unminimizeAll(appElement: appElement)
                        let freshWindows = appElement.getWindows().filter { $0.isGatherableWindow }
                        let frames = LayoutEngine.layout(windowCount: freshWindows.count, in: region, gap: 0)
                        // Retry setFrame multiple times — freshly launched apps
                        // may ignore size changes until fully initialized
                        for pass in 0..<3 {
                            for (j, window) in freshWindows.enumerated() where j < frames.count {
                                window.setFrame(frames[j])
                            }
                            if pass < 2 {
                                Thread.sleep(forTimeInterval: 0.5)
                            }
                        }
                        Thread.sleep(forTimeInterval: 0.2)
                        verifyAndFixStrays(freshWindows, frames: frames)
                        for window in freshWindows.reversed() {
                            window.raise()
                            Thread.sleep(forTimeInterval: 0.01)
                        }
                        continuation.resume()
                    }
                }
                return
            }
        }
        // 15s timeout — app is running but never showed a window; nothing to layout
    }

    // MARK: - Screen targeting (Approach B)

    /// Get the visible frame of the screen under the cursor, in AX coordinates.
    @MainActor
    private static func cursorScreenFrame() -> CGRect {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else {
            return CGRect(x: 0, y: 0, width: 1440, height: 900)
        }

        return visibleFrameInAXCoords(for: screen)
    }

    /// Convert a screen's visibleFrame from AppKit coords (bottom-left origin)
    /// to AX/screen coords (top-left origin, y-down).
    private static func visibleFrameInAXCoords(for screen: NSScreen) -> CGRect {
        let visible = screen.visibleFrame
        // AX global coords use primary screen's top-left as origin
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        return CGRect(
            x: visible.origin.x,
            y: mainHeight - visible.origin.y - visible.height,
            width: visible.width,
            height: visible.height
        )
    }

    // MARK: - Gather

    private static func performGather(app: AppInfo, maximize: Bool, targetFrame: CGRect) {
        guard let pid = app.pid else { return }
        let appElement = AccessibilityElement.from(pid: pid)
        appElement.setTimeout(1.0)

        exitFullscreen(appElement: appElement)
        activateApp(pid: pid)
        unminimizeAll(appElement: appElement)

        var windows = appElement.getWindows().filter { $0.isGatherableWindow }
        if windows.isEmpty {
            // App is running but has no windows (e.g., Spotify with window closed).
            // Plain activate() isn't enough — use openApplication to trigger the app's
            // reopen handler (applicationShouldHandleReopen), which recreates the window.
            if let bundleURL = app.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
                    semaphore.signal()
                }
                semaphore.wait(timeout: .now() + 3.0)
            }
            // Poll for the window to appear
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.5)
                windows = appElement.getWindows().filter { $0.isGatherableWindow }
                if !windows.isEmpty { break }
            }
            guard !windows.isEmpty else { return }
        }

        let gap: CGFloat = maximize ? 0 : 10
        layoutWindows(windows, in: targetFrame, maximize: maximize, gap: gap)

        if windows.count > 1 || maximize {
            let frames = LayoutEngine.layout(windowCount: windows.count, in: targetFrame, gap: gap)
            verifyAndFixStrays(windows, frames: frames)
        }

        raiseWindows(windows, appElement: appElement, pid: pid)
    }

    // MARK: - Split

    private static func performSplit(apps: [AppInfo], targetFrame: CGRect, rightSide: Bool = false) {
        guard !apps.isEmpty else { return }

        // Compute region for each app (equal columns for 2-3, 2x2 for 4)
        let regions = LayoutEngine.splitLayout(appCount: apps.count, in: targetFrame, gap: 0, rightSide: rightSide)
        guard regions.count == apps.count else { return }

        // Prepare AX elements (skip non-running apps)
        let elements = apps.map { app -> AccessibilityElement? in
            guard let pid = app.pid else { return nil }
            let el = AccessibilityElement.from(pid: pid)
            el.setTimeout(1.0)
            return el
        }

        // Exit fullscreen on all running apps before any activation
        for el in elements {
            guard let el else { continue }
            exitFullscreen(appElement: el)
        }

        // Per-app activate → unminimize → layout (same proven pattern as gather).
        var allWindowSets: [[AccessibilityElement]] = []
        for (i, (app, el)) in zip(apps, elements).enumerated() {
            guard let pid = app.pid, let el else {
                allWindowSets.append([])
                continue
            }
            activateApp(pid: pid)
            unminimizeAll(appElement: el)
            var windows = el.getWindows().filter { $0.isGatherableWindow }
            // Running app with 0 windows: trigger reopen (e.g., Spotify with window closed)
            if windows.isEmpty, let bundleURL = app.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                let semaphore = DispatchSemaphore(value: 0)
                Task {
                    _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: config)
                    semaphore.signal()
                }
                semaphore.wait(timeout: .now() + 3.0)
                for _ in 0..<10 {
                    Thread.sleep(forTimeInterval: 0.5)
                    windows = el.getWindows().filter { $0.isGatherableWindow }
                    if !windows.isEmpty { break }
                }
            }
            allWindowSets.append(windows)
            layoutWindows(windows, in: regions[i], maximize: true, gap: 0)
        }

        // Re-apply pass: fix any windows displaced by later app activations
        Thread.sleep(forTimeInterval: 0.1)
        for (i, windows) in allWindowSets.enumerated() {
            let frames = LayoutEngine.layout(windowCount: windows.count, in: regions[i], gap: 0)
            for (j, window) in windows.enumerated() where j < frames.count {
                window.setFrame(frames[j])
            }
        }

        // Stray verification on each region
        for (i, windows) in allWindowSets.enumerated() where !windows.isEmpty {
            let frames = LayoutEngine.layout(windowCount: windows.count, in: regions[i], gap: 0)
            verifyAndFixStrays(windows, frames: frames)
        }

        // Raise in reverse order so first app ends on top with focus
        for windows in allWindowSets.reversed() {
            for window in windows.reversed() {
                window.raise()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        // Give first running app keyboard focus
        if let firstEl = elements.first, let el = firstEl {
            el.setFrontmost(true)
        }
    }

    // MARK: - Shared Helpers

    /// Exit fullscreen for all windows of an app. Blocks until animations complete.
    private static func exitFullscreen(appElement: AccessibilityElement) {
        let windows = appElement.getWindows()
        var hadFullScreen = false
        for window in windows where window.isFullScreen {
            window.setFullScreen(false)
            hadFullScreen = true
        }
        if hadFullScreen {
            let deadline = Date().addingTimeInterval(2.0)
            while Date() < deadline {
                if !windows.contains(where: { $0.isFullScreen }) { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            // AXFullScreen flips false mid-animation — wait for it to fully complete.
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    /// Activate an app by PID on the main thread.
    private static func activateApp(pid: pid_t) {
        DispatchQueue.main.sync {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        Thread.sleep(forTimeInterval: 0.15)
    }

    /// Unminimize all windows of an app. Needs app active to work reliably.
    private static func unminimizeAll(appElement: AccessibilityElement) {
        let windows = appElement.getWindows()
        var hadMinimized = false
        for window in windows where window.isMinimized {
            window.unminimize()
            hadMinimized = true
        }
        if hadMinimized {
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    /// Layout windows within a target rect.
    /// Single window + !maximize: center at current size. Otherwise: tile via LayoutEngine.
    private static func layoutWindows(_ windows: [AccessibilityElement], in rect: CGRect, maximize: Bool, gap: CGFloat = 10) {
        guard !windows.isEmpty else { return }

        if windows.count == 1 && !maximize {
            let window = windows[0]
            if let currentSize = window.getSize() {
                let x = rect.midX - currentSize.width / 2
                let y = rect.midY - currentSize.height / 2
                let clampedX = max(rect.minX, min(x, rect.maxX - currentSize.width))
                let clampedY = max(rect.minY, min(y, rect.maxY - currentSize.height))
                window.setPosition(CGPoint(x: clampedX, y: clampedY))
            }
        } else {
            let frames = LayoutEngine.layout(windowCount: windows.count, in: rect, gap: gap)
            for (i, window) in windows.enumerated() where i < frames.count {
                window.setFrame(frames[i])
                if i < windows.count - 1 {
                    Thread.sleep(forTimeInterval: 0.02)
                }
            }
            // Compact rows for maximize/split: close gaps from apps that snap to
            // discrete sizes (e.g., Terminal character grid). No-op for apps like
            // Finder that already tile perfectly.
            if gap == 0 && windows.count >= 4 {
                let cols = Int(ceil(sqrt(Double(windows.count))))
                compactGrid(windows, cols: cols)
            }
        }
    }

    /// After grid layout with gap=0, read back actual window sizes and reposition
    /// to close row gaps and prevent column overlaps caused by apps that snap
    /// window sizes to discrete increments (e.g., Terminal character grid).
    /// No-op for apps that already tile perfectly (e.g., Finder).
    private static func compactGrid(_ windows: [AccessibilityElement], cols: Int) {
        let rows = Int(ceil(Double(windows.count) / Double(cols)))
        guard rows > 1 || cols > 1 else { return }

        // Small delay to let AX finish processing setFrame calls
        Thread.sleep(forTimeInterval: 0.03)

        // Read back actual sizes from AX
        let actualSizes: [CGSize?] = windows.map { $0.getSize() }

        // Max actual width per column (across all rows)
        var colWidths = [CGFloat](repeating: 0, count: cols)
        for i in 0..<windows.count {
            if let size = actualSizes[i] {
                colWidths[i % cols] = max(colWidths[i % cols], size.width)
            }
        }

        // Max actual height per row (across all columns)
        var rowHeights = [CGFloat](repeating: 0, count: rows)
        for i in 0..<windows.count {
            if let size = actualSizes[i] {
                rowHeights[i / cols] = max(rowHeights[i / cols], size.height)
            }
        }

        // Use first window's position as grid origin
        guard let origin = windows[0].getPosition() else { return }

        // Compute column X positions from cumulative actual widths
        var colX = [CGFloat](repeating: 0, count: cols)
        colX[0] = origin.x
        for c in 1..<cols {
            colX[c] = colX[c - 1] + colWidths[c - 1]
        }

        // Compute row Y positions from cumulative actual heights
        var rowY = [CGFloat](repeating: 0, count: rows)
        rowY[0] = origin.y
        for r in 1..<rows {
            rowY[r] = rowY[r - 1] + rowHeights[r - 1]
        }

        // Reposition only windows that need adjustment (>1px off)
        for i in 0..<windows.count {
            guard let pos = windows[i].getPosition() else { continue }
            let targetX = colX[i % cols]
            let targetY = rowY[i / cols]
            if abs(pos.x - targetX) > 1 || abs(pos.y - targetY) > 1 {
                windows[i].setPosition(CGPoint(x: targetX, y: targetY))
            }
        }
    }

    /// Two-pass stray window detection and force-move.
    private static func verifyAndFixStrays(_ windows: [AccessibilityElement], frames: [CGRect]) {
        for pass in 0..<2 {
            Thread.sleep(forTimeInterval: pass == 0 ? 0.05 : 0.4)
            var allLanded = true
            for (i, window) in windows.enumerated() where i < frames.count {
                guard let actual = window.getPosition() else { continue }
                let intended = frames[i].origin
                if abs(actual.x - intended.x) > 50 || abs(actual.y - intended.y) > 50 {
                    allLanded = false
                    window.setPosition(intended)
                    window.setSize(frames[i].size)
                    window.setPosition(intended)
                }
            }
            if allLanded { break }
        }
    }

    /// Raise all windows and set app frontmost. Reverse order so window[0] ends on top.
    private static func raiseWindows(_ windows: [AccessibilityElement], appElement: AccessibilityElement, pid: pid_t) {
        appElement.setFrontmost(true)
        DispatchQueue.main.sync {
            NSRunningApplication(processIdentifier: pid)?.activate()
        }
        Thread.sleep(forTimeInterval: 0.1)
        for window in windows.reversed() {
            window.raise()
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
