import AppKit
import SwiftUI

// MARK: - View Model

@MainActor
class OnboardingViewModel: NSObject, ObservableObject, NSWindowDelegate {
    enum Mode: Equatable {
        case tutorial
        case whatsNew
    }

    @Published var mode: Mode = .tutorial
    @Published var currentStep: OnboardingStep = .welcome
    @Published var stepCompleted: Bool = false
    @Published var whatsNewFeatures: [WhatsNewFeature] = []

    private var observers: [NSObjectProtocol] = []

    func startTutorial(fromStep: OnboardingStep = .welcome) {
        mode = .tutorial
        currentStep = fromStep
        stepCompleted = false
        installObserverForCurrentStep()
    }

    func startWhatsNew(_ features: [WhatsNewFeature]) {
        mode = .whatsNew
        whatsNewFeatures = features
        removeNotificationObservers()
    }

    func advanceStep() {
        guard mode == .tutorial else { return }
        let allSteps = OnboardingStep.allCases
        guard let currentIndex = allSteps.firstIndex(of: currentStep),
              currentIndex + 1 < allSteps.count else {
            complete()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = allSteps[currentIndex + 1]
            stepCompleted = false
        }
        OnboardingTracker.currentStep = currentStep
        installObserverForCurrentStep()
    }

    func skipTutorial() {
        complete()
    }

    func dismissWhatsNew() {
        OnboardingTracker.lastShownVersion = OnboardingTracker.currentAppVersion
        OnboardingManager.shared.dismiss()
    }

    private func complete() {
        OnboardingTracker.markCompleted()
        OnboardingManager.shared.dismiss()
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Save progress but don't mark as completed
        if mode == .tutorial && currentStep != .complete {
            OnboardingTracker.currentStep = currentStep
        } else if mode == .whatsNew {
            OnboardingTracker.lastShownVersion = OnboardingTracker.currentAppVersion
        }
        removeNotificationObservers()
    }

    // MARK: - Notification Monitoring

    /// Subscribe only to the specific notification for the current step.
    private func installObserverForCurrentStep() {
        removeNotificationObservers()
        guard mode == .tutorial else { return }
        guard let notificationName = currentStep.completionNotification else { return }

        let obs = NotificationCenter.default.addObserver(
            forName: notificationName, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.mode == .tutorial, !self.stepCompleted else { return }
                withAnimation(.spring(response: 0.4)) {
                    self.stepCompleted = true
                }
                // Auto-advance after a brief pause so user sees the checkmark
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.advanceStep()
                }
            }
        }
        observers.append(obs)
    }

    func removeNotificationObservers() {
        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()
    }
}

// MARK: - Onboarding Manager

/// Manages the onboarding window lifecycle. Follows SettingsManager pattern.
@MainActor
class OnboardingManager {
    static let shared = OnboardingManager()

    private var window: NSWindow?
    private var viewModel: OnboardingViewModel?

    private init() {}

    func create() {
        let vm = OnboardingViewModel()
        self.viewModel = vm

        let contentView = OnboardingView(viewModel: vm)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Convoker"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = vm

        self.window = window
    }

    func showTutorial() {
        guard let window, let viewModel else { return }
        viewModel.startTutorial()
        window.title = "Welcome to Convoker"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showWhatsNew(_ features: [WhatsNewFeature]) {
        guard let window, let viewModel else { return }
        viewModel.startWhatsNew(features)
        window.title = "What's New in Convoker"
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func dismiss() {
        viewModel?.removeNotificationObservers()
        window?.orderOut(nil)
    }
}
