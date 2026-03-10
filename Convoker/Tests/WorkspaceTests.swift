@testable import Convoker
import XCTest

/// Tests for Workspace model and WorkspaceStore persistence.
final class WorkspaceTests: XCTestCase {

    // MARK: - Model

    func testWorkspace_init() {
        let ws = Workspace(
            name: "Coding",
            assignments: [
                AppAssignment(bundleID: "com.apple.dt.Xcode", appName: "Xcode", screen: .primary, region: .leftHalf),
                AppAssignment(bundleID: "com.apple.Terminal", appName: "Terminal", screen: .primary, region: .rightHalf),
            ]
        )
        XCTAssertEqual(ws.name, "Coding")
        XCTAssertEqual(ws.assignments.count, 2)
        XCTAssertTrue(ws.hideOthers)
        XCTAssertEqual(ws.appSummary, "Xcode + Terminal")
    }

    func testAppAssignment_defaults() {
        let a = AppAssignment(bundleID: "com.test.app", appName: "TestApp", screen: .cursor, region: .full)
        XCTAssertTrue(a.launchIfNeeded)
        XCTAssertEqual(a.screen, .cursor)
    }

    func testScreenTarget_rawValues() {
        XCTAssertEqual(ScreenTarget.primary.rawValue, "primary")
        XCTAssertEqual(ScreenTarget.secondary.rawValue, "secondary")
        XCTAssertEqual(ScreenTarget.tertiary.rawValue, "tertiary")
        XCTAssertEqual(ScreenTarget.cursor.rawValue, "cursor")
    }

    // MARK: - Codable

    func testWorkspace_codableRoundTrip() throws {
        let ws = Workspace(
            name: "Research",
            assignments: [
                AppAssignment(bundleID: "com.apple.Safari", appName: "Safari", screen: .primary, region: .full),
                AppAssignment(bundleID: "com.apple.Notes", appName: "Notes", screen: .secondary, region: .leftHalf),
            ],
            hideOthers: false
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(ws)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Workspace.self, from: data)

        XCTAssertEqual(decoded.name, "Research")
        XCTAssertEqual(decoded.assignments.count, 2)
        XCTAssertFalse(decoded.hideOthers)
        XCTAssertEqual(decoded.assignments[0].region, .full)
        XCTAssertEqual(decoded.assignments[1].screen, .secondary)
    }

    // MARK: - WorkspaceStore

    func testStore_saveAndLoad() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspaces_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = WorkspaceStore(fileURL: tempURL)
        XCTAssertTrue(store.workspaces.isEmpty)

        let ws = Workspace(
            name: "Test",
            assignments: [
                AppAssignment(bundleID: "com.test.app", appName: "Test", screen: .primary, region: .full)
            ]
        )
        store.save(ws)
        XCTAssertEqual(store.workspaces.count, 1)

        // Reload from file
        let store2 = WorkspaceStore(fileURL: tempURL)
        XCTAssertEqual(store2.workspaces.count, 1)
        XCTAssertEqual(store2.workspaces[0].name, "Test")
    }

    func testStore_saveOrOverwrite_newWorkspace() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspaces_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = WorkspaceStore(fileURL: tempURL)
        let ws = store.saveOrOverwrite(
            name: "coding",
            assignments: [
                AppAssignment(bundleID: "com.apple.dt.Xcode", appName: "Xcode", screen: .primary, region: .leftHalf)
            ]
        )
        XCTAssertEqual(ws.name, "coding")
        XCTAssertEqual(store.workspaces.count, 1)
    }

    func testStore_saveOrOverwrite_overwriteExisting() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspaces_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = WorkspaceStore(fileURL: tempURL)

        // First save
        _ = store.saveOrOverwrite(
            name: "coding",
            assignments: [
                AppAssignment(bundleID: "com.apple.dt.Xcode", appName: "Xcode", screen: .primary, region: .full)
            ]
        )

        // Overwrite with same name (case-insensitive)
        let ws2 = store.saveOrOverwrite(
            name: "Coding",
            assignments: [
                AppAssignment(bundleID: "com.apple.dt.Xcode", appName: "Xcode", screen: .primary, region: .leftHalf),
                AppAssignment(bundleID: "com.apple.Terminal", appName: "Terminal", screen: .primary, region: .rightHalf),
            ]
        )

        XCTAssertEqual(store.workspaces.count, 1) // still 1 workspace
        XCTAssertEqual(ws2.assignments.count, 2)
    }

    func testStore_delete() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspaces_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = WorkspaceStore(fileURL: tempURL)
        let ws = store.saveOrOverwrite(
            name: "temp",
            assignments: [
                AppAssignment(bundleID: "com.test.app", appName: "Test", screen: .primary, region: .full)
            ]
        )
        XCTAssertEqual(store.workspaces.count, 1)

        store.delete(ws)
        XCTAssertEqual(store.workspaces.count, 0)
    }

    func testStore_search() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspaces_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = WorkspaceStore(fileURL: tempURL)
        _ = store.saveOrOverwrite(name: "coding", assignments: [])
        _ = store.saveOrOverwrite(name: "communication", assignments: [])
        _ = store.saveOrOverwrite(name: "research", assignments: [])

        let results = store.search(query: "cod")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "coding")

        let all = store.search(query: "")
        XCTAssertEqual(all.count, 3)
    }

    func testStore_workspaceNamed() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_workspaces_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let store = WorkspaceStore(fileURL: tempURL)
        _ = store.saveOrOverwrite(name: "Coding", assignments: [])

        XCTAssertNotNil(store.workspace(named: "coding"))  // case-insensitive
        XCTAssertNotNil(store.workspace(named: "Coding"))
        XCTAssertNil(store.workspace(named: "research"))
    }
}
