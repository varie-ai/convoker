@testable import Convoker
import XCTest

final class OnboardingStateTests: XCTestCase {
    private var originalDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        originalDefaults = OnboardingTracker.defaults
        let testDefaults = UserDefaults(suiteName: "com.convoker.tests.\(UUID().uuidString)")!
        OnboardingTracker.defaults = testDefaults
    }

    override func tearDown() {
        OnboardingTracker.defaults = originalDefaults
        super.tearDown()
    }

    // MARK: - Launch Action

    func testLaunchAction_firstLaunch_returnsFullTutorial() {
        // Fresh defaults = never completed
        if case .fullTutorial = OnboardingTracker.launchAction() {
            // expected
        } else {
            XCTFail("Expected .fullTutorial on first launch")
        }
    }

    func testLaunchAction_completedAtCurrentVersion_returnsNone() {
        OnboardingTracker.hasCompletedOnboarding = true
        OnboardingTracker.lastShownVersion = OnboardingTracker.currentAppVersion

        if case .none = OnboardingTracker.launchAction() {
            // expected
        } else {
            XCTFail("Expected .none when completed at current version")
        }
    }

    func testLaunchAction_completedAtOlderVersion_returnsWhatsNew() {
        OnboardingTracker.hasCompletedOnboarding = true
        OnboardingTracker.lastShownVersion = "0.1.0"

        if case .whatsNew(let features) = OnboardingTracker.launchAction() {
            XCTAssertFalse(features.isEmpty)
        } else {
            XCTFail("Expected .whatsNew when completed at older version")
        }
    }

    func testLaunchAction_notCompleted_alwaysReturnsTutorial() {
        // Even with a version set, if not completed, show tutorial
        OnboardingTracker.hasCompletedOnboarding = false
        OnboardingTracker.lastShownVersion = "0.1.0"

        if case .fullTutorial = OnboardingTracker.launchAction() {
            // expected
        } else {
            XCTFail("Expected .fullTutorial when not completed")
        }
    }

    // MARK: - Mark Completed

    func testMarkCompleted_setsAllFlags() {
        OnboardingTracker.markCompleted()

        XCTAssertTrue(OnboardingTracker.hasCompletedOnboarding)
        XCTAssertEqual(OnboardingTracker.lastShownVersion, OnboardingTracker.currentAppVersion)
        XCTAssertEqual(OnboardingTracker.currentStep, .complete)
    }

    // MARK: - Current Step Persistence

    func testCurrentStep_defaultsToWelcome() {
        XCTAssertEqual(OnboardingTracker.currentStep, .welcome)
    }

    func testCurrentStep_persists() {
        OnboardingTracker.currentStep = .focusMode
        XCTAssertEqual(OnboardingTracker.currentStep, .focusMode)
    }

    func testCurrentStep_allCasesRoundTrip() {
        for step in OnboardingStep.allCases {
            OnboardingTracker.currentStep = step
            XCTAssertEqual(OnboardingTracker.currentStep, step)
        }
    }

    // MARK: - Version Comparison

    func testVersionComparison_newerMajor() {
        XCTAssertTrue(WhatsNewContent.compareVersions("2.0.0", isNewerThan: "1.0.0"))
    }

    func testVersionComparison_newerMinor() {
        XCTAssertTrue(WhatsNewContent.compareVersions("0.4.0", isNewerThan: "0.3.0"))
    }

    func testVersionComparison_newerPatch() {
        XCTAssertTrue(WhatsNewContent.compareVersions("0.4.1", isNewerThan: "0.4.0"))
    }

    func testVersionComparison_same() {
        XCTAssertFalse(WhatsNewContent.compareVersions("0.4.0", isNewerThan: "0.4.0"))
    }

    func testVersionComparison_older() {
        XCTAssertFalse(WhatsNewContent.compareVersions("0.3.0", isNewerThan: "0.4.0"))
    }

    func testVersionComparison_differentLengths() {
        XCTAssertTrue(WhatsNewContent.compareVersions("0.4.1", isNewerThan: "0.4"))
        XCTAssertFalse(WhatsNewContent.compareVersions("0.4", isNewerThan: "0.4.1"))
    }

    func testVersionComparison_emptyString() {
        XCTAssertTrue(WhatsNewContent.compareVersions("0.1.0", isNewerThan: ""))
    }

    // MARK: - What's New Content

    func testWhatsNewContent_sinceEmpty_returnsAll() {
        let features = WhatsNewContent.features(since: "")
        XCTAssertNotNil(features)
        XCTAssertGreaterThanOrEqual(features!.count, 5)
    }

    func testWhatsNewContent_since030_returnsV04Features() {
        let features = WhatsNewContent.features(since: "0.3.0")
        XCTAssertNotNil(features)
        XCTAssertEqual(features!.count, 1)
        XCTAssertEqual(features!.first?.title, "Workspaces")
    }

    func testWhatsNewContent_sinceCurrentVersion_returnsNil() {
        // No features newer than the latest registered version
        let features = WhatsNewContent.features(since: "99.0.0")
        XCTAssertNil(features)
    }

    // MARK: - Step Properties

    func testInteractiveSteps_haveNotifications() {
        let interactive: [OnboardingStep] = [.openPalette, .searchApp, .gatherWindows, .focusMode, .splitView, .workspaces]
        for step in interactive {
            XCTAssertTrue(step.isInteractive, "\(step) should be interactive")
            XCTAssertNotNil(step.completionNotification, "\(step) should have a notification")
        }
    }

    func testManualSteps_haveNoNotifications() {
        let manual: [OnboardingStep] = [.welcome, .complete]
        for step in manual {
            XCTAssertFalse(step.isInteractive, "\(step) should not be interactive")
            XCTAssertNil(step.completionNotification, "\(step) should have no notification")
        }
    }

    func testAllSteps_haveTitleAndDescription() {
        for step in OnboardingStep.allCases {
            XCTAssertFalse(step.title.isEmpty, "\(step) should have a title")
            XCTAssertFalse(step.description.isEmpty, "\(step) should have a description")
            XCTAssertFalse(step.iconName.isEmpty, "\(step) should have an icon")
        }
    }
}
