import XCTest

/// Tests for the AppKit-to-AX coordinate conversion formula.
/// AppKit: origin at bottom-left, y increases upward.
/// AX:     origin at top-left, y increases downward.
/// Formula: ax_y = mainScreenHeight - appkit_y - height
final class CoordinateConversionTests: XCTestCase {

    /// Convert AppKit coordinates to AX coordinates.
    /// This mirrors the logic in WindowGatherer.visibleFrameInAXCoords().
    private func appKitToAX(
        appKitFrame: CGRect,
        mainScreenHeight: CGFloat
    ) -> CGRect {
        CGRect(
            x: appKitFrame.origin.x,
            y: mainScreenHeight - appKitFrame.origin.y - appKitFrame.height,
            width: appKitFrame.width,
            height: appKitFrame.height
        )
    }

    func testConversion_bottomLeftWindow() {
        // AppKit: window at bottom-left corner of 1080p screen
        let frame = appKitToAX(
            appKitFrame: CGRect(x: 0, y: 0, width: 500, height: 300),
            mainScreenHeight: 1080
        )
        // AX: should be at bottom-left (high y value)
        XCTAssertEqual(frame.origin.x, 0)
        XCTAssertEqual(frame.origin.y, 780) // 1080 - 0 - 300
        XCTAssertEqual(frame.width, 500)
        XCTAssertEqual(frame.height, 300)
    }

    func testConversion_topLeftWindow() {
        // AppKit: window at top-left (y = screenHeight - windowHeight)
        let frame = appKitToAX(
            appKitFrame: CGRect(x: 0, y: 780, width: 500, height: 300),
            mainScreenHeight: 1080
        )
        // AX: should be at top-left (y = 0)
        XCTAssertEqual(frame.origin.y, 0)
    }

    func testConversion_centeredWindow() {
        // AppKit: centered on 1920x1080 screen
        let frame = appKitToAX(
            appKitFrame: CGRect(x: 460, y: 290, width: 1000, height: 500),
            mainScreenHeight: 1080
        )
        // AX: x stays the same, y flips
        XCTAssertEqual(frame.origin.x, 460)
        XCTAssertEqual(frame.origin.y, 290) // 1080 - 290 - 500 = 290 (centered!)
        XCTAssertEqual(frame.width, 1000)
        XCTAssertEqual(frame.height, 500)
    }

    func testConversion_fullScreen() {
        let frame = appKitToAX(
            appKitFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
            mainScreenHeight: 1080
        )
        // Full screen in both coordinate systems
        XCTAssertEqual(frame, CGRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testConversion_withMenuBar() {
        // AppKit visibleFrame excludes menu bar (25px at top)
        // visibleFrame: y=0, height=1055 (screen is 1080, menu bar 25)
        let frame = appKitToAX(
            appKitFrame: CGRect(x: 0, y: 0, width: 1920, height: 1055),
            mainScreenHeight: 1080
        )
        // AX: y should be 25 (below menu bar)
        XCTAssertEqual(frame.origin.y, 25) // 1080 - 0 - 1055 = 25
    }

    func testConversion_secondScreen_negative_x() {
        // Second screen to the left: x is negative in AppKit
        let frame = appKitToAX(
            appKitFrame: CGRect(x: -1920, y: 200, width: 800, height: 600),
            mainScreenHeight: 1080
        )
        // x stays negative, y flips
        XCTAssertEqual(frame.origin.x, -1920)
        XCTAssertEqual(frame.origin.y, 280) // 1080 - 200 - 600
    }

    func testConversion_roundTrip() {
        // Converting twice should NOT return to original (not symmetric)
        // But converting and then converting back with inverse should
        let original = CGRect(x: 100, y: 200, width: 500, height: 300)
        let mainHeight: CGFloat = 1080

        let ax = appKitToAX(appKitFrame: original, mainScreenHeight: mainHeight)
        // Inverse: appKit_y = mainHeight - ax_y - height
        let roundTrip = CGRect(
            x: ax.origin.x,
            y: mainHeight - ax.origin.y - ax.height,
            width: ax.width,
            height: ax.height
        )
        XCTAssertEqual(roundTrip, original)
    }
}
