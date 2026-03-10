@testable import Convoker
import XCTest

/// Tests for Region normalized rect type, resolve, and inference.
final class RegionTests: XCTestCase {

    // MARK: - Named Regions

    func testNamedRegions_coverScreen() {
        // Full region should cover entire screen
        XCTAssertEqual(Region.full.x, 0)
        XCTAssertEqual(Region.full.y, 0)
        XCTAssertEqual(Region.full.width, 1)
        XCTAssertEqual(Region.full.height, 1)
    }

    func testNamedRegions_halves() {
        XCTAssertEqual(Region.leftHalf.width, 0.5)
        XCTAssertEqual(Region.rightHalf.width, 0.5)
        XCTAssertEqual(Region.leftHalf.x, 0)
        XCTAssertEqual(Region.rightHalf.x, 0.5)
    }

    func testNamedRegions_quadrants() {
        let quadrants: [Region] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        for q in quadrants {
            XCTAssertEqual(q.width, 0.5)
            XCTAssertEqual(q.height, 0.5)
        }
        XCTAssertEqual(Region.topLeft.x, 0)
        XCTAssertEqual(Region.topLeft.y, 0)
        XCTAssertEqual(Region.bottomRight.x, 0.5)
        XCTAssertEqual(Region.bottomRight.y, 0.5)
    }

    // MARK: - Resolve

    func testResolve_full_matchesScreen() {
        let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let resolved = Region.full.resolve(in: screen)
        XCTAssertEqual(resolved.minX, 0, accuracy: 0.1)
        XCTAssertEqual(resolved.minY, 25, accuracy: 0.1)
        XCTAssertEqual(resolved.width, 1440, accuracy: 0.1)
        XCTAssertEqual(resolved.height, 875, accuracy: 0.1)
    }

    func testResolve_leftHalf() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let resolved = Region.leftHalf.resolve(in: screen)
        XCTAssertEqual(resolved.width, 500, accuracy: 0.1)
        XCTAssertEqual(resolved.height, 800, accuracy: 0.1)
    }

    func testResolve_withGap() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let resolved = Region.full.resolve(in: screen, gap: 20)
        // Gap applies as inset: dx=10, dy=10
        XCTAssertEqual(resolved.minX, 10, accuracy: 0.1)
        XCTAssertEqual(resolved.minY, 10, accuracy: 0.1)
        XCTAssertEqual(resolved.width, 980, accuracy: 0.1)
        XCTAssertEqual(resolved.height, 780, accuracy: 0.1)
    }

    func testResolve_secondScreen_offset() {
        // Second screen at x=1440
        let screen = CGRect(x: 1440, y: 0, width: 2560, height: 1440)
        let resolved = Region.rightHalf.resolve(in: screen)
        XCTAssertEqual(resolved.minX, 1440 + 1280, accuracy: 0.1)
        XCTAssertEqual(resolved.width, 1280, accuracy: 0.1)
    }

    // MARK: - Inference

    func testInfer_fullScreen_snaps() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 10, y: 5, width: 1420, height: 890)
        let region = Region.infer(from: window, in: screen, tolerance: 0.1)
        XCTAssertEqual(region, .full)
    }

    func testInfer_leftHalf_snaps() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = CGRect(x: 5, y: 5, width: 715, height: 890)
        let region = Region.infer(from: window, in: screen, tolerance: 0.1)
        XCTAssertEqual(region, .leftHalf)
    }

    func testInfer_customPosition_noSnap() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        // A window at 30% x, 40% width — doesn't match any named region well
        let window = CGRect(x: 432, y: 0, width: 576, height: 900)
        let region = Region.infer(from: window, in: screen, tolerance: 0.05)
        // Should return custom fraction, not a named region
        XCTAssertNotEqual(region, .leftHalf)
        XCTAssertNotEqual(region, .rightHalf)
        XCTAssertNotEqual(region, .full)
        XCTAssertEqual(region.x, 0.3, accuracy: 0.01)
        XCTAssertEqual(region.width, 0.4, accuracy: 0.01)
    }

    // MARK: - Display Name

    func testDisplayName_namedRegion() {
        XCTAssertEqual(Region.full.displayName, "Full")
        XCTAssertEqual(Region.leftHalf.displayName, "Left Half")
        XCTAssertEqual(Region.topRight.displayName, "Top Right")
    }

    func testDisplayName_customRegion() {
        let custom = Region(x: 0.1, y: 0.2, width: 0.6, height: 0.8)
        XCTAssertEqual(custom.displayName, "60% x 80%")
    }

    // MARK: - Split Regions

    func testSplitRegions_twoApps_halves() {
        let regions = Region.splitRegions(count: 2)
        XCTAssertEqual(regions.count, 2)
        XCTAssertEqual(regions[0], .leftHalf)
        XCTAssertEqual(regions[1], .rightHalf)
    }

    func testSplitRegions_threeApps_thirds() {
        let regions = Region.splitRegions(count: 3)
        XCTAssertEqual(regions.count, 3)
        // Each should be ~1/3 width
        for r in regions {
            XCTAssertEqual(r.width, 1.0/3.0, accuracy: 0.01)
            XCTAssertEqual(r.height, 1.0, accuracy: 0.01)
        }
    }

    func testSplitRegions_fourApps_grid() {
        let regions = Region.splitRegions(count: 4)
        XCTAssertEqual(regions.count, 4)
        // 2x2 grid: each should be 0.5 x 0.5
        for r in regions {
            XCTAssertEqual(r.width, 0.5, accuracy: 0.01)
            XCTAssertEqual(r.height, 0.5, accuracy: 0.01)
        }
    }

    func testSplitRegions_singleApp_full() {
        let regions = Region.splitRegions(count: 1)
        XCTAssertEqual(regions, [.full])
    }

    func testSplitRegions_zeroApps_empty() {
        let regions = Region.splitRegions(count: 0)
        XCTAssertTrue(regions.isEmpty)
    }

    // MARK: - Distance

    func testDistance_sameRegion_zero() {
        XCTAssertEqual(Region.full.distance(to: .full), 0, accuracy: 0.001)
    }

    func testDistance_symmetric() {
        let d1 = Region.leftHalf.distance(to: .rightHalf)
        let d2 = Region.rightHalf.distance(to: .leftHalf)
        XCTAssertEqual(d1, d2, accuracy: 0.001)
    }

    // MARK: - Codable

    func testCodable_roundTrip() throws {
        let region = Region(x: 0.1, y: 0.2, width: 0.6, height: 0.8)
        let data = try JSONEncoder().encode(region)
        let decoded = try JSONDecoder().decode(Region.self, from: data)
        XCTAssertEqual(region, decoded)
    }

    func testCodable_namedRegion() throws {
        let data = try JSONEncoder().encode(Region.leftHalf)
        let decoded = try JSONDecoder().decode(Region.self, from: data)
        XCTAssertEqual(decoded, .leftHalf)
    }
}
