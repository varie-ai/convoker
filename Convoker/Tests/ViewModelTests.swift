@testable import Convoker
import XCTest

/// Tests for CommandPaletteViewModel state machine logic.
/// These tests focus on pure state transitions (selection, pin/unpin, mode).
@MainActor
final class ViewModelTests: XCTestCase {

    // Helper: create mock AppInfo (running app)
    private func mockApp(_ name: String, id: String? = nil, running: Bool = true) -> AppInfo {
        AppInfo(
            id: id ?? name.lowercased(),
            name: name,
            bundleID: "com.test.\(name.lowercased())",
            pid: running ? pid_t(Int32.random(in: 1000...9999)) : nil,
            icon: nil,
            windowCount: running ? 2 : 0,
            bundleURL: nil
        )
    }

    /// Set filteredItems from an array of mock apps (wraps in PaletteItem.app).
    private func setItems(_ vm: CommandPaletteViewModel, _ apps: [AppInfo]) {
        vm.filteredItems = apps.map { .app($0) }
    }

    // MARK: - moveSelection

    func testMoveSelectionDown_fromNil_selectsFirst() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari"), mockApp("Chrome"), mockApp("Firefox")])
        vm.selectedIndex = nil

        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 0)
    }

    func testMoveSelectionUp_fromNil_selectsLast() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari"), mockApp("Chrome"), mockApp("Firefox")])
        vm.selectedIndex = nil

        vm.moveSelection(by: -1)
        XCTAssertEqual(vm.selectedIndex, 2)
    }

    func testMoveSelection_wrapsForward() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari"), mockApp("Chrome")])
        vm.selectedIndex = 1

        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 0) // wraps to start
    }

    func testMoveSelection_wrapsBackward() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari"), mockApp("Chrome")])
        vm.selectedIndex = 0

        vm.moveSelection(by: -1)
        XCTAssertEqual(vm.selectedIndex, 1) // wraps to end
    }

    func testMoveSelection_emptyList_noOp() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [])
        vm.selectedIndex = nil

        vm.moveSelection(by: 1)
        XCTAssertNil(vm.selectedIndex)
    }

    func testMoveSelection_singleItem_staysAtZero() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari")])
        vm.selectedIndex = 0

        vm.moveSelection(by: 1)
        XCTAssertEqual(vm.selectedIndex, 0) // (0+1) % 1 = 0
    }

    // MARK: - Pin / Unpin

    func testPinSelected_addsToStack() {
        let vm = CommandPaletteViewModel()
        let safari = mockApp("Safari")
        setItems(vm, [safari, mockApp("Chrome")])
        vm.selectedIndex = 0

        vm.pinSelected()

        XCTAssertEqual(vm.pinnedApps.count, 1)
        XCTAssertEqual(vm.pinnedApps[0].name, "Safari")
        XCTAssertTrue(vm.isPinned)
        XCTAssertEqual(vm.searchText, "")
        XCTAssertNil(vm.selectedIndex)
    }

    func testPinSelected_maxThreePins() {
        let vm = CommandPaletteViewModel()
        let apps = (1...5).map { mockApp("App\($0)", id: "app\($0)") }

        // Pin 3 apps
        for i in 0..<3 {
            setItems(vm, apps)
            vm.selectedIndex = i
            vm.pinSelected()
        }
        XCTAssertEqual(vm.pinnedApps.count, 3)

        // Try to pin a 4th — should be no-op
        setItems(vm, apps)
        vm.selectedIndex = 3
        vm.pinSelected()
        XCTAssertEqual(vm.pinnedApps.count, 3) // still 3
    }

    func testPinSelected_noSelection_noOp() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari")])
        vm.selectedIndex = nil

        vm.pinSelected()
        XCTAssertFalse(vm.isPinned)
    }

    func testUnpin_removesLast() {
        let vm = CommandPaletteViewModel()
        vm.mode = .pinned(apps: [mockApp("Safari"), mockApp("Chrome")])

        vm.unpin()
        XCTAssertEqual(vm.pinnedApps.count, 1)
        XCTAssertEqual(vm.pinnedApps[0].name, "Safari")
        XCTAssertTrue(vm.isPinned)
    }

    func testUnpin_lastPinReturnsToNormal() {
        let vm = CommandPaletteViewModel()
        vm.mode = .pinned(apps: [mockApp("Safari")])

        vm.unpin()
        XCTAssertFalse(vm.isPinned)
        if case .normal = vm.mode {} else {
            XCTFail("Mode should be .normal after unpinning last app")
        }
    }

    func testUnpin_resetsSearchAndSelection() {
        let vm = CommandPaletteViewModel()
        vm.mode = .pinned(apps: [mockApp("Safari"), mockApp("Chrome")])
        vm.searchText = "fire"
        vm.selectedIndex = 2

        vm.unpin()
        XCTAssertEqual(vm.searchText, "")
        XCTAssertNil(vm.selectedIndex)
    }

    // MARK: - Mode

    func testPinnedApps_normalMode_returnsEmpty() {
        let vm = CommandPaletteViewModel()
        vm.mode = .normal
        XCTAssertTrue(vm.pinnedApps.isEmpty)
        XCTAssertFalse(vm.isPinned)
    }

    func testPinnedApps_pinnedMode_returnsApps() {
        let apps = [mockApp("Safari"), mockApp("Chrome")]
        let vm = CommandPaletteViewModel()
        vm.mode = .pinned(apps: apps)
        XCTAssertEqual(vm.pinnedApps.count, 2)
    }

    // MARK: - executeAction dispatch

    func testExecuteAction_normalNoSelection_noOp() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari")])
        vm.selectedIndex = nil
        vm.mode = .normal

        // Should not crash — just a no-op
        vm.executeAction()
        // Verify nothing changed (no crash = pass)
    }

    // MARK: - updateFiltered

    func testUpdateFiltered_clampsOverflowSelection() {
        let vm = CommandPaletteViewModel()
        setItems(vm, [mockApp("Safari"), mockApp("Chrome")])
        vm.selectedIndex = 5 // overflow

        vm.updateFiltered()
        // After update, selectedIndex should be clamped
        if let idx = vm.selectedIndex {
            XCTAssertLessThan(idx, vm.filteredItems.count)
        }
    }

    func testUpdateFiltered_nilSelectionOnEmptySearch() {
        let vm = CommandPaletteViewModel()
        vm.searchText = ""

        vm.updateFiltered()
        XCTAssertNil(vm.selectedIndex)
    }

    // MARK: - Workspace Mode

    func testSaveMode_enterAndExit() {
        let vm = CommandPaletteViewModel()
        vm.enterSaveMode()
        XCTAssertTrue(vm.isSaving)
        XCTAssertEqual(vm.searchText, "")
        XCTAssertTrue(vm.filteredItems.isEmpty)

        // Exit save mode via escape (simulated)
        vm.mode = .normal
        vm.updateFiltered()
        XCTAssertFalse(vm.isSaving)
    }

    func testIsSaveKeyword() {
        let vm = CommandPaletteViewModel()
        vm.searchText = "save"
        XCTAssertTrue(vm.isSaveKeyword)

        vm.searchText = "Save"
        XCTAssertTrue(vm.isSaveKeyword)

        vm.searchText = "  save  "
        XCTAssertTrue(vm.isSaveKeyword)

        vm.searchText = "safari"
        XCTAssertFalse(vm.isSaveKeyword)
    }
}
