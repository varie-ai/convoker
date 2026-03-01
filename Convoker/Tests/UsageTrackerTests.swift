@testable import Convoker
import XCTest

final class UsageTrackerTests: XCTestCase {
    private var originalDefaults: UserDefaults!

    override func setUp() {
        super.setUp()
        // Use isolated UserDefaults suite for each test
        originalDefaults = UsageTracker.defaults
        let testDefaults = UserDefaults(suiteName: "com.convoker.tests.\(UUID().uuidString)")!
        UsageTracker.defaults = testDefaults
    }

    override func tearDown() {
        UsageTracker.defaults = originalDefaults
        super.tearDown()
    }

    func testRecordAction_incrementsCount() {
        UsageTracker.recordAction(bundleID: "com.apple.Safari")
        XCTAssertEqual(UsageTracker.count(for: "com.apple.Safari"), 1)
    }

    func testRecordAction_multipleIncrements() {
        let id = "com.apple.Terminal"
        UsageTracker.recordAction(bundleID: id)
        UsageTracker.recordAction(bundleID: id)
        UsageTracker.recordAction(bundleID: id)
        XCTAssertEqual(UsageTracker.count(for: id), 3)
    }

    func testRecordAction_independentBundleIDs() {
        UsageTracker.recordAction(bundleID: "com.apple.Safari")
        UsageTracker.recordAction(bundleID: "com.apple.Safari")
        UsageTracker.recordAction(bundleID: "com.apple.Terminal")
        XCTAssertEqual(UsageTracker.count(for: "com.apple.Safari"), 2)
        XCTAssertEqual(UsageTracker.count(for: "com.apple.Terminal"), 1)
    }

    func testCountForNilBundleID_returnsZero() {
        XCTAssertEqual(UsageTracker.count(for: nil), 0)
    }

    func testRecordActionNilBundleID_noOp() {
        UsageTracker.recordAction(bundleID: nil)
        XCTAssertTrue(UsageTracker.allCounts().isEmpty)
    }

    func testCountForUnknownBundleID_returnsZero() {
        XCTAssertEqual(UsageTracker.count(for: "com.unknown.app"), 0)
    }

    func testAllCounts_returnsAllRecorded() {
        UsageTracker.recordAction(bundleID: "com.app.one")
        UsageTracker.recordAction(bundleID: "com.app.two")
        UsageTracker.recordAction(bundleID: "com.app.two")

        let counts = UsageTracker.allCounts()
        XCTAssertEqual(counts.count, 2)
        XCTAssertEqual(counts["com.app.one"], 1)
        XCTAssertEqual(counts["com.app.two"], 2)
    }

    func testAllCounts_emptyByDefault() {
        XCTAssertTrue(UsageTracker.allCounts().isEmpty)
    }
}
