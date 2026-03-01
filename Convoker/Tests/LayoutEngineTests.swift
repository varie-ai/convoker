@testable import Convoker
import XCTest

final class LayoutEngineTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)
    let gap: CGFloat = 10

    override func setUp() {
        super.setUp()
        UserDefaults.standard.set("grid", forKey: "gatherLayout")
        UserDefaults.standard.set("equal", forKey: "splitRatio")
    }

    // MARK: - SplitRatio

    func testSplitRatioEqualFraction() {
        XCTAssertEqual(SplitRatio.equal.leftFraction, 0.5)
    }

    func testSplitRatioSixtyFortyFraction() {
        XCTAssertEqual(SplitRatio.sixtyForty.leftFraction, 0.6)
    }

    func testSplitRatioSeventyThirtyFraction() {
        XCTAssertEqual(SplitRatio.seventyThirty.leftFraction, 0.7)
    }

    // MARK: - layout() — Grid mode

    func testLayoutZeroWindows_returnsEmpty() {
        let result = LayoutEngine.layout(windowCount: 0, in: screen, gap: gap)
        XCTAssertTrue(result.isEmpty)
    }

    func testLayoutOneWindow_fillsAreaWithInset() {
        let result = LayoutEngine.layout(windowCount: 1, in: screen, gap: gap)
        XCTAssertEqual(result.count, 1)
        // area = screen.insetBy(dx: 10, dy: 10) = (10, 10, 1900, 1060)
        let expected = CGRect(x: 10, y: 10, width: 1900, height: 1060)
        XCTAssertEqual(result[0], expected)
    }

    func testLayoutTwoWindows_sideBySide() {
        let result = LayoutEngine.layout(windowCount: 2, in: screen, gap: gap)
        XCTAssertEqual(result.count, 2)

        // area = (10, 10, 1900, 1060)
        // halfWidth = (1900 - 10) / 2 = 945
        let halfWidth = (1900.0 - gap) / 2
        XCTAssertEqual(result[0].origin.x, 10)
        XCTAssertEqual(result[0].width, halfWidth, accuracy: 0.01)
        XCTAssertEqual(result[1].origin.x, 10 + halfWidth + gap, accuracy: 0.01)
        XCTAssertEqual(result[1].width, halfWidth, accuracy: 0.01)
        // Both full height
        XCTAssertEqual(result[0].height, 1060)
        XCTAssertEqual(result[1].height, 1060)
    }

    func testLayoutThreeWindows_leftHalfPlusRightSplit() {
        let result = LayoutEngine.layout(windowCount: 3, in: screen, gap: gap)
        XCTAssertEqual(result.count, 3)

        // area = (10, 10, 1900, 1060)
        let halfWidth = (1900.0 - gap) / 2
        let halfHeight = (1060.0 - gap) / 2

        // First window: left half, full height
        XCTAssertEqual(result[0].origin.x, 10)
        XCTAssertEqual(result[0].width, halfWidth, accuracy: 0.01)
        XCTAssertEqual(result[0].height, 1060)

        // Second window: right top
        XCTAssertEqual(result[1].origin.x, 10 + halfWidth + gap, accuracy: 0.01)
        XCTAssertEqual(result[1].origin.y, 10)
        XCTAssertEqual(result[1].height, halfHeight, accuracy: 0.01)

        // Third window: right bottom
        XCTAssertEqual(result[2].origin.x, 10 + halfWidth + gap, accuracy: 0.01)
        XCTAssertEqual(result[2].origin.y, 10 + halfHeight + gap, accuracy: 0.01)
        XCTAssertEqual(result[2].height, halfHeight, accuracy: 0.01)
    }

    func testLayoutFourWindows_2x2Grid() {
        let result = LayoutEngine.layout(windowCount: 4, in: screen, gap: gap)
        XCTAssertEqual(result.count, 4)

        // ceil(sqrt(4)) = 2 cols, ceil(4/2) = 2 rows
        let area = screen.insetBy(dx: gap, dy: gap)
        let cellWidth = (area.width - gap) / 2
        let cellHeight = (area.height - gap) / 2

        // Top-left
        XCTAssertEqual(result[0].origin.x, area.minX, accuracy: 0.01)
        XCTAssertEqual(result[0].origin.y, area.minY, accuracy: 0.01)
        XCTAssertEqual(result[0].width, cellWidth, accuracy: 0.01)
        XCTAssertEqual(result[0].height, cellHeight, accuracy: 0.01)

        // Top-right
        XCTAssertEqual(result[1].origin.x, area.minX + cellWidth + gap, accuracy: 0.01)
        XCTAssertEqual(result[1].origin.y, area.minY, accuracy: 0.01)

        // Bottom-left
        XCTAssertEqual(result[2].origin.x, area.minX, accuracy: 0.01)
        XCTAssertEqual(result[2].origin.y, area.minY + cellHeight + gap, accuracy: 0.01)

        // Bottom-right
        XCTAssertEqual(result[3].origin.x, area.minX + cellWidth + gap, accuracy: 0.01)
        XCTAssertEqual(result[3].origin.y, area.minY + cellHeight + gap, accuracy: 0.01)
    }

    func testLayoutFiveWindows_3colGrid() {
        let result = LayoutEngine.layout(windowCount: 5, in: screen, gap: gap)
        XCTAssertEqual(result.count, 5)

        // ceil(sqrt(5)) = 3 cols, ceil(5/3) = 2 rows
        let area = screen.insetBy(dx: gap, dy: gap)
        let cellWidth = (area.width - gap * 2) / 3
        let cellHeight = (area.height - gap) / 2

        // Row 0: 3 windows
        for i in 0..<3 {
            XCTAssertEqual(result[i].origin.y, area.minY, accuracy: 0.01)
            XCTAssertEqual(result[i].width, cellWidth, accuracy: 0.01)
            XCTAssertEqual(result[i].height, cellHeight, accuracy: 0.01)
        }
        // Row 1: 2 windows
        for i in 3..<5 {
            XCTAssertEqual(result[i].origin.y, area.minY + cellHeight + gap, accuracy: 0.01)
        }
    }

    func testLayoutNineWindows_3x3Grid() {
        let result = LayoutEngine.layout(windowCount: 9, in: screen, gap: gap)
        XCTAssertEqual(result.count, 9)

        // ceil(sqrt(9)) = 3 cols, ceil(9/3) = 3 rows
        let area = screen.insetBy(dx: gap, dy: gap)
        let cellWidth = (area.width - gap * 2) / 3
        let cellHeight = (area.height - gap * 2) / 3

        for i in 0..<9 {
            XCTAssertEqual(result[i].width, cellWidth, accuracy: 0.01)
            XCTAssertEqual(result[i].height, cellHeight, accuracy: 0.01)
        }
    }

    // MARK: - layout() — Cascade mode

    func testLayoutCascade_offsetsFromTopLeft() {
        UserDefaults.standard.set("cascade", forKey: "gatherLayout")
        let result = LayoutEngine.layout(windowCount: 3, in: screen, gap: gap)
        XCTAssertEqual(result.count, 3)

        let area = screen.insetBy(dx: gap, dy: gap)
        let windowWidth = area.width * 0.7
        let windowHeight = area.height * 0.7

        // All same size
        for frame in result {
            XCTAssertEqual(frame.width, windowWidth, accuracy: 0.01)
            XCTAssertEqual(frame.height, windowHeight, accuracy: 0.01)
        }

        // Increasing offset
        XCTAssertEqual(result[0].origin.x, area.minX)
        XCTAssertEqual(result[1].origin.x, area.minX + 30)
        XCTAssertEqual(result[2].origin.x, area.minX + 60)
    }

    func testLayoutCascade_clampsToBounds() {
        UserDefaults.standard.set("cascade", forKey: "gatherLayout")
        // Many windows — offsets should clamp to keep windows in area
        let result = LayoutEngine.layout(windowCount: 50, in: screen, gap: gap)
        XCTAssertEqual(result.count, 50)

        let area = screen.insetBy(dx: gap, dy: gap)
        let windowWidth = area.width * 0.7

        // Last window should be clamped (not beyond area)
        let last = result.last!
        XCTAssertLessThanOrEqual(last.maxX, area.maxX + 0.01)
        XCTAssertLessThanOrEqual(last.maxY, area.maxY + 0.01)
        XCTAssertEqual(last.origin.x, area.maxX - windowWidth, accuracy: 0.01)
    }

    // MARK: - layout() — Side-by-side (columns) mode

    func testLayoutColumns_equalWidthColumns() {
        UserDefaults.standard.set("sideBySide", forKey: "gatherLayout")
        let result = LayoutEngine.layout(windowCount: 4, in: screen, gap: gap)
        XCTAssertEqual(result.count, 4)

        let area = screen.insetBy(dx: gap, dy: gap)
        let colWidth = (area.width - gap * 3) / 4

        for i in 0..<4 {
            XCTAssertEqual(result[i].width, colWidth, accuracy: 0.01)
            XCTAssertEqual(result[i].height, area.height, accuracy: 0.01)
        }
    }

    // MARK: - splitLayout()

    func testSplitLayoutOneApp_leftPortion() {
        let result = LayoutEngine.splitLayout(appCount: 1, in: screen, gap: 0)
        XCTAssertEqual(result.count, 1)
        // Equal ratio: left half
        XCTAssertEqual(result[0].origin.x, 0)
        XCTAssertEqual(result[0].width, 960, accuracy: 0.01) // 1920 * 0.5
        XCTAssertEqual(result[0].height, 1080)
    }

    func testSplitLayoutOneApp_rightPortion() {
        let result = LayoutEngine.splitLayout(appCount: 1, in: screen, gap: 0, rightSide: true)
        XCTAssertEqual(result.count, 1)
        // Equal ratio: right half
        XCTAssertEqual(result[0].origin.x, 960, accuracy: 0.01)
        XCTAssertEqual(result[0].width, 960, accuracy: 0.01)
    }

    func testSplitLayoutOneApp_respectsSixtyFortyRatio() {
        UserDefaults.standard.set("sixtyForty", forKey: "splitRatio")
        let result = LayoutEngine.splitLayout(appCount: 1, in: screen, gap: 0)
        XCTAssertEqual(result[0].width, 1920 * 0.6, accuracy: 0.01) // 1152
    }

    func testSplitLayoutTwoApps_equalRatio() {
        let result = LayoutEngine.splitLayout(appCount: 2, in: screen, gap: 0)
        XCTAssertEqual(result.count, 2)
        // 50/50 split
        XCTAssertEqual(result[0].width, 960, accuracy: 0.01)
        XCTAssertEqual(result[1].width, 960, accuracy: 0.01)
        XCTAssertEqual(result[0].height, 1080)
        XCTAssertEqual(result[1].height, 1080)
    }

    func testSplitLayoutTwoApps_seventyThirtyRatio() {
        UserDefaults.standard.set("seventyThirty", forKey: "splitRatio")
        let result = LayoutEngine.splitLayout(appCount: 2, in: screen, gap: 0)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].width, 1920 * 0.7, accuracy: 0.01) // 1344
        XCTAssertEqual(result[1].width, 1920 * 0.3, accuracy: 0.01) // 576
    }

    func testSplitLayoutThreeApps_equalThirds() {
        let result = LayoutEngine.splitLayout(appCount: 3, in: screen, gap: 0)
        XCTAssertEqual(result.count, 3)
        let thirdWidth = 1920.0 / 3
        for frame in result {
            XCTAssertEqual(frame.width, thirdWidth, accuracy: 0.01)
            XCTAssertEqual(frame.height, 1080)
        }
    }

    func testSplitLayoutFourApps_2x2Grid() {
        let result = LayoutEngine.splitLayout(appCount: 4, in: screen, gap: 0)
        XCTAssertEqual(result.count, 4)
        // 2x2 grid: each cell is 960x540
        for frame in result {
            XCTAssertEqual(frame.width, 960, accuracy: 0.01)
            XCTAssertEqual(frame.height, 540, accuracy: 0.01)
        }
    }

    // MARK: - Edge cases

    func testLayoutWithGapZero() {
        let result = LayoutEngine.layout(windowCount: 1, in: screen, gap: 0)
        XCTAssertEqual(result[0], screen)
    }

    func testSplitLayoutZeroApps_returnsEmpty() {
        let result = LayoutEngine.splitLayout(appCount: 0, in: screen)
        XCTAssertTrue(result.isEmpty)
    }

    func testLayoutFramesCoverScreen() {
        // All frames should be within the screen bounds (with gap inset)
        for count in 1...10 {
            let result = LayoutEngine.layout(windowCount: count, in: screen, gap: gap)
            let area = screen.insetBy(dx: gap, dy: gap)
            for frame in result {
                XCTAssertGreaterThanOrEqual(frame.minX, area.minX - 0.01,
                    "Window at index overflows left for count=\(count)")
                XCTAssertGreaterThanOrEqual(frame.minY, area.minY - 0.01,
                    "Window at index overflows top for count=\(count)")
                XCTAssertLessThanOrEqual(frame.maxX, area.maxX + 0.01,
                    "Window at index overflows right for count=\(count)")
                XCTAssertLessThanOrEqual(frame.maxY, area.maxY + 0.01,
                    "Window at index overflows bottom for count=\(count)")
            }
        }
    }

    func testLayoutFrameCount_matchesWindowCount() {
        for count in 0...20 {
            let result = LayoutEngine.layout(windowCount: count, in: screen, gap: gap)
            XCTAssertEqual(result.count, count)
        }
    }

    func testSplitLayoutFrameCount_matchesAppCount() {
        for count in 0...4 {
            let result = LayoutEngine.splitLayout(appCount: count, in: screen, gap: 0)
            XCTAssertEqual(result.count, count)
        }
    }
}
