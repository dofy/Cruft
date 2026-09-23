import XCTest
@testable import Cruft

final class CruftTests: XCTestCase {
    func testBTMParserDeduplicatesUUIDAndKeepsNewestGeneration() {
        let dump = """
        #1:
            UUID: DUPLICATE-UUID
            Name: Example Agent
            Type: agent (0x8)
            Disposition: [disabled, allowed, notified] (0xa)
            Identifier: old.example
            URL: /tmp/old-example
            Generation: 1

        #2:
            UUID: DUPLICATE-UUID
            Name: Example Agent
            Type: agent (0x8)
            Disposition: [enabled, allowed, notified] (0xb)
            Identifier: new.example
            URL: /tmp/new-example
            Generation: 3
        """

        let items = BTM.parse(dump)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].identifier, "new.example")
        XCTAssertTrue(items[0].isEnabled)
    }

    @MainActor
    func testCleanerDoesNotScanFoldersBeforeAuthorization() {
        let viewModel = CleanerViewModel()

        XCTAssertFalse(viewModel.hasFolderAccess)
        XCTAssertTrue(viewModel.sizes.isEmpty)
    }

    func testInstalledApplicationScanReturnsAppBundles() {
        let apps = AppScanner.installedApplications()

        XCTAssertFalse(apps.isEmpty)
        XCTAssertTrue(apps.allSatisfy { $0.path.hasSuffix(".app") })
    }

    func testChromePWAUsesTypeLabelInsteadOfVersion() {
        let app = InstalledApplication(
            path: "/Applications/Example.app",
            name: "Example",
            bundleIdentifier: "com.google.Chrome.app.abcdefghijklmnop",
            version: "",
            size: 0,
            modified: .distantPast
        )

        XCTAssertTrue(app.isChromePWA)
        XCTAssertNil(app.displayVersion)
        XCTAssertEqual(app.versionLabel, "Chrome PWA")
    }

    func testMissingApplicationVersionHasNoDisplayValue() {
        let app = InstalledApplication(
            path: "/Applications/Example.app",
            name: "Example",
            bundleIdentifier: "com.example.app",
            version: "   ",
            size: 0,
            modified: .distantPast
        )

        XCTAssertFalse(app.isChromePWA)
        XCTAssertNil(app.displayVersion)
        // "v N/A" 走字符串目录，跟着界面语言变，所以比的是同一个 key 而不是字面量。
        XCTAssertEqual(
            app.versionLabel,
            String(localized: "app.version.unknown", defaultValue: "v N/A")
        )
    }

    func testBundleIdentifierMatchesAreExact() {
        let preference = AppScanner.association(
            entryName: "com.example.Editor.plist",
            appName: "Editor",
            bundleIdentifier: "com.example.Editor"
        )
        let helper = AppScanner.association(
            entryName: "com.example.Editor.helper",
            appName: "Editor",
            bundleIdentifier: "com.example.Editor"
        )

        XCTAssertEqual(preference?.confidence, .exact)
        XCTAssertEqual(helper?.confidence, .exact)
    }

    func testNameOnlyMatchIsConservative() {
        let result = AppScanner.association(
            entryName: "Pixelmator Pro",
            appName: "Pixelmator Pro",
            bundleIdentifier: "com.pixelmatorteam.pixelmator.x"
        )

        XCTAssertEqual(result?.confidence, .likely)
    }

    func testUnrelatedEntryDoesNotMatch() {
        let result = AppScanner.association(
            entryName: "com.apple.Safari.plist",
            appName: "Editor",
            bundleIdentifier: "com.example.Editor"
        )

        XCTAssertNil(result)
    }

    func testTrashTargetGuardBlocksBroadDirectories() {
        XCTAssertFalse(FileCleaner.isSafeTrashTarget("/"))
        XCTAssertFalse(FileCleaner.isSafeTrashTarget(NSHomeDirectory()))
        XCTAssertFalse(FileCleaner.isSafeTrashTarget("/Applications"))
        XCTAssertTrue(FileCleaner.isSafeTrashTarget("\(NSHomeDirectory())/Library/Caches/example"))
        XCTAssertTrue(FileCleaner.isSafeTrashTarget("/Applications/Example.app"))
        XCTAssertFalse(FileCleaner.isSafeTrashTarget("/Applications/LooseFile.txt"))
    }

    func testRestoreMovesItemBackToOriginalPath() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CruftTests-\(UUID().uuidString)")
        let mockTrash = root.appendingPathComponent("Trash")
        let original = root.appendingPathComponent("Original/item.txt")
        let trashed = mockTrash.appendingPathComponent("item.txt")
        try fm.createDirectory(at: mockTrash, withIntermediateDirectories: true)
        try Data("recover me".utf8).write(to: trashed)
        defer { try? fm.removeItem(at: root) }

        let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path, size: 10)
        let result = DeletionHistoryStore.restoreItems([item])

        XCTAssertEqual(result.restored, [item])
        XCTAssertTrue(fm.fileExists(atPath: original.path))
        XCTAssertFalse(fm.fileExists(atPath: trashed.path))
    }

    func testRestoreNeverOverwritesExistingFile() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("CruftTests-\(UUID().uuidString)")
        let original = root.appendingPathComponent("Original/item.txt")
        let trashed = root.appendingPathComponent("Trash/item.txt")
        try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: trashed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: original)
        try Data("old file".utf8).write(to: trashed)
        defer { try? fm.removeItem(at: root) }

        let item = TrashedItem(originalPath: original.path, trashedPath: trashed.path, size: 8)
        let result = DeletionHistoryStore.restoreItems([item])

        XCTAssertEqual(result.failed, [item])
        XCTAssertEqual(try String(contentsOf: original), "keep me")
        XCTAssertTrue(fm.fileExists(atPath: trashed.path))
    }
}
