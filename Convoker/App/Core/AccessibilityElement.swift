import AppKit

/// Lightweight AXUIElement wrapper focused on window operations.
/// Inspired by Rectangle's AccessibilityElement.swift.
struct AccessibilityElement {
    let element: AXUIElement

    // MARK: - Constructors

    /// Create from a running application's PID.
    static func from(pid: pid_t) -> AccessibilityElement {
        AccessibilityElement(element: AXUIElementCreateApplication(pid))
    }

    /// Create the system-wide element.
    static func systemWide() -> AccessibilityElement {
        AccessibilityElement(element: AXUIElementCreateSystemWide())
    }

    // MARK: - Window Discovery

    /// Get all windows for this application element.
    func getWindows() -> [AccessibilityElement] {
        guard let value: CFArray = getAttribute(kAXWindowsAttribute as CFString) else {
            return []
        }
        let windows = value as [AnyObject]
        return windows.compactMap { obj in
            // Each object is an AXUIElement
            let el = obj as! AXUIElement
            return AccessibilityElement(element: el)
        }
    }

    // MARK: - Attributes

    func getTitle() -> String? {
        getAttribute(kAXTitleAttribute as CFString)
    }

    func getRole() -> String? {
        getAttribute(kAXRoleAttribute as CFString)
    }

    func getSubrole() -> String? {
        getAttribute(kAXSubroleAttribute as CFString)
    }

    func getPosition() -> CGPoint? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &value)
        guard error == .success, let val = value else { return nil }
        var point = CGPoint.zero
        AXValueGetValue(val as! AXValue, .cgPoint, &point)
        return point
    }

    func getSize() -> CGSize? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &value)
        guard error == .success, let val = value else { return nil }
        var size = CGSize.zero
        AXValueGetValue(val as! AXValue, .cgSize, &size)
        return size
    }

    func getFrame() -> CGRect? {
        guard let position = getPosition(), let size = getSize() else { return nil }
        return CGRect(origin: position, size: size)
    }

    var isMinimized: Bool {
        let val: CFTypeRef? = getAttribute(kAXMinimizedAttribute as CFString)
        return (val as? Bool) ?? false
    }

    var isFullScreen: Bool {
        let val: CFTypeRef? = getAttribute("AXFullScreen" as CFString)
        return (val as? Bool) ?? false
    }

    /// Check if this has the window role.
    var isWindow: Bool {
        getRole() == kAXWindowRole
    }

    /// Check if this is a gatherable window.
    /// Permissive: any AXWindow that isn't a popover, sheet, or system dialog.
    /// Chrome/Electron apps sometimes use non-standard subroles.
    var isGatherableWindow: Bool {
        guard isWindow else { return false }
        let subrole = getSubrole()
        // Exclude known non-window subroles
        let excluded: Set<String> = [
            kAXFloatingWindowSubrole as String,
            kAXSystemFloatingWindowSubrole as String,
        ]
        if let subrole, excluded.contains(subrole) { return false }
        // Accept everything else (standard, dialog, Chrome's custom, nil subrole)
        return true
    }

    // MARK: - Mutations

    func setPosition(_ point: CGPoint) {
        var p = point
        let value = AXValueCreate(.cgPoint, &p)!
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    func setSize(_ size: CGSize) {
        var s = size
        let value = AXValueCreate(.cgSize, &s)!
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }

    /// Move and resize using the size-position-size pattern.
    /// Sets size first, then position, then size again to handle macOS display clamping.
    func setFrame(_ frame: CGRect) {
        setSize(frame.size)
        setPosition(frame.origin)
        setSize(frame.size)
    }

    func unminimize() {
        AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, false as CFBoolean)
    }

    func setFullScreen(_ value: Bool) {
        AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, value as CFBoolean)
    }

    func raise() {
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
    }

    /// Set this app element as the frontmost application via AX.
    func setFrontmost(_ value: Bool) {
        AXUIElementSetAttributeValue(element, kAXFrontmostAttribute as CFString, value as CFBoolean)
    }

    // MARK: - Timeout

    /// Set messaging timeout to avoid blocking on unresponsive apps.
    func setTimeout(_ seconds: Float) {
        AXUIElementSetMessagingTimeout(element, seconds)
    }

    // MARK: - Private Helpers

    private func getAttribute<T>(_ attribute: CFString) -> T? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard error == .success else { return nil }
        return value as? T
    }
}
