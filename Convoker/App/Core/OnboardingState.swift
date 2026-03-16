import Foundation

// MARK: - Notification Names

extension Notification.Name {
    static let convokerPaletteDidShow = Notification.Name("convokerPaletteDidShow")
    static let convokerSearchDidType = Notification.Name("convokerSearchDidType")
    static let convokerDidGather = Notification.Name("convokerDidGather")
    static let convokerDidFocus = Notification.Name("convokerDidFocus")
    static let convokerDidPinForSplit = Notification.Name("convokerDidPinForSplit")
    static let convokerDidSplit = Notification.Name("convokerDidSplit")
    static let convokerDidSaveWorkspace = Notification.Name("convokerDidSaveWorkspace")
}

// MARK: - Onboarding Step

/// The steps of the interactive onboarding tutorial.
enum OnboardingStep: Int, Codable, CaseIterable {
    case welcome = 0
    case openPalette = 1
    case searchApp = 2
    case gatherWindows = 3
    case focusMode = 4
    case splitView = 5
    case workspaces = 6
    case complete = 7

    /// The notification that completes this step. nil = manual advance via button.
    var completionNotification: Notification.Name? {
        switch self {
        case .welcome:       return nil
        case .openPalette:   return .convokerPaletteDidShow
        case .searchApp:     return .convokerSearchDidType
        case .gatherWindows: return .convokerDidGather
        case .focusMode:     return .convokerDidFocus
        case .splitView:     return .convokerDidSplit
        case .workspaces:    return .convokerDidSaveWorkspace
        case .complete:      return nil
        }
    }

    /// Whether the user needs to actually perform the action (vs. click Next).
    var isInteractive: Bool {
        completionNotification != nil
    }

    var title: String {
        switch self {
        case .welcome:       return "Welcome to Convoker"
        case .openPalette:   return "Open the Command Palette"
        case .searchApp:     return "Search for an App"
        case .gatherWindows: return "Gather Windows"
        case .focusMode:     return "Focus Mode"
        case .splitView:     return "Split View"
        case .workspaces:    return "Save a Workspace"
        case .complete:      return "You're All Set!"
        }
    }

    var description: String {
        switch self {
        case .welcome:
            return "Convoker lets you manage all windows of any app at once — gather, focus, split, and save layouts. No other tool does this.\n\nLet's walk through the basics."
        case .openPalette:
            return "Press Cmd+Shift+X to summon the command palette. It floats above everything and lets you pick any app.\n\nTry it now!"
        case .searchApp:
            return "Start typing any app name. Convoker fuzzy-matches running apps and can even launch installed ones.\n\nType at least 2 characters in the palette."
        case .gatherWindows:
            return "With an app selected, press Enter to gather all its windows to your current screen. Shift+Enter maximizes them too.\n\nSelect an app and press Enter."
        case .focusMode:
            return "Press Cmd+Enter to activate an app and hide everything else. Instant distraction-free focus.\n\nOpen the palette, select an app, and press Cmd+Enter."
        case .splitView:
            return "Press Tab to pin an app as the left side, then search a second app and press Enter for side-by-side.\n\nPin an app with Tab, pick another, and press Enter."
        case .workspaces:
            return "Type \"save\" in the palette — or press Cmd+Shift+S — to save your current window layout as a workspace. Recall it anytime by searching the workspace name.\n\nOpen the palette and type \"save\" (or use Cmd+Shift+S)."
        case .complete:
            return "You'll find Convoker in your menu bar. Open Settings to customize your hotkey, layout style, and split ratio.\n\nHappy window managing!"
        }
    }

    var iconName: String {
        switch self {
        case .welcome:       return "app.gift"
        case .openPalette:   return "command.square"
        case .searchApp:     return "text.magnifyingglass"
        case .gatherWindows: return "rectangle.3.group"
        case .focusMode:     return "eye"
        case .splitView:     return "rectangle.split.2x1"
        case .workspaces:    return "square.and.arrow.down"
        case .complete:      return "checkmark.circle"
        }
    }

    var shortcutHint: String? {
        switch self {
        case .openPalette:   return "⌘⇧X"
        case .gatherWindows: return "⏎"
        case .focusMode:     return "⌘⏎"
        case .splitView:     return "TAB  then  ⏎"
        case .workspaces:    return "\"save\"  or  ⌘⇧S"
        default:             return nil
        }
    }
}

// MARK: - Onboarding Action

/// What to show on app launch.
enum OnboardingAction {
    case fullTutorial
    case whatsNew([WhatsNewFeature])
    case none
}

// MARK: - Onboarding Tracker

/// Persists onboarding state in UserDefaults. Follows the UsageTracker pattern.
enum OnboardingTracker {
    private static let hasCompletedKey = "hasCompletedOnboarding"
    private static let lastVersionKey = "lastShownOnboardingVersion"
    private static let currentStepKey = "onboardingCurrentStep"

    static var defaults: UserDefaults = .standard

    static var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: hasCompletedKey) }
        set { defaults.set(newValue, forKey: hasCompletedKey) }
    }

    static var lastShownVersion: String {
        get { defaults.string(forKey: lastVersionKey) ?? "" }
        set { defaults.set(newValue, forKey: lastVersionKey) }
    }

    static var currentStep: OnboardingStep {
        get {
            let raw = defaults.integer(forKey: currentStepKey)
            return OnboardingStep(rawValue: raw) ?? .welcome
        }
        set { defaults.set(newValue.rawValue, forKey: currentStepKey) }
    }

    static var currentAppVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    /// Determine what to show on launch.
    static func launchAction() -> OnboardingAction {
        if !hasCompletedOnboarding {
            return .fullTutorial
        }
        if lastShownVersion != currentAppVersion,
           let newFeatures = WhatsNewContent.features(since: lastShownVersion),
           !newFeatures.isEmpty {
            return .whatsNew(newFeatures)
        }
        return .none
    }

    static func markCompleted() {
        hasCompletedOnboarding = true
        lastShownVersion = currentAppVersion
        currentStep = .complete
    }
}

// MARK: - What's New

struct WhatsNewFeature {
    let title: String
    let description: String
    let iconName: String
}

enum WhatsNewContent {
    private static let versionFeatures: [(version: String, features: [WhatsNewFeature])] = [
        ("0.2.0", [
            WhatsNewFeature(
                title: "Focus Mode",
                description: "Cmd+Enter activates an app and hides all others.",
                iconName: "eye"
            ),
            WhatsNewFeature(
                title: "Split View",
                description: "Tab to pin an app, pick a second, Enter for side-by-side.",
                iconName: "rectangle.split.2x1"
            ),
        ]),
        ("0.3.0", [
            WhatsNewFeature(
                title: "App Launcher",
                description: "Search and launch any installed app, not just running ones.",
                iconName: "magnifyingglass"
            ),
            WhatsNewFeature(
                title: "Settings",
                description: "Customize layout style, split ratio, and launch at login.",
                iconName: "gearshape"
            ),
        ]),
        ("0.4.0", [
            WhatsNewFeature(
                title: "Workspaces",
                description: "Save and recall multi-app window layouts across screens.",
                iconName: "rectangle.3.group"
            ),
        ]),
    ]

    /// Returns features added since the given version, or nil if none.
    static func features(since version: String) -> [WhatsNewFeature]? {
        let newFeatures = versionFeatures
            .filter { compareVersions($0.version, isNewerThan: version) }
            .flatMap(\.features)
        return newFeatures.isEmpty ? nil : newFeatures
    }

    /// Simple semver comparison: returns true if `a` is strictly newer than `b`.
    static func compareVersions(_ a: String, isNewerThan b: String) -> Bool {
        let aParts = a.split(separator: ".").compactMap { Int($0) }
        let bParts = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(aParts.count, bParts.count) {
            let aVal = i < aParts.count ? aParts[i] : 0
            let bVal = i < bParts.count ? bParts[i] : 0
            if aVal > bVal { return true }
            if aVal < bVal { return false }
        }
        return false
    }
}
