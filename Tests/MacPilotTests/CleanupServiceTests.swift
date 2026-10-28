import XCTest
@testable import MacPilot

final class CleanupServiceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testScanExcludesSymlinksAndLooseFiles() throws {
        let cache = try folder("app.cache")
        try Data(repeating: 1, count: 8192).write(to: cache.appendingPathComponent("data"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: cache)
        try Data([1]).write(to: root.appendingPathComponent("loose"))
        let scan = try CleanupService.scan(root: root)
        XCTAssertEqual(scan.entries.map(\.name), ["app.cache"])
        XCTAssertEqual(scan.skipped, 2)
        XCTAssertGreaterThan(scan.entries[0].bytes, 0)
    }

    func testRejectsRootNestedAndOutsidePaths() throws {
        let child = try folder("child")
        let nested = child.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertTrue(CleanupService.isEligible(child, root: root))
        XCTAssertFalse(CleanupService.isEligible(root, root: root))
        XCTAssertFalse(CleanupService.isEligible(nested, root: root))
        XCTAssertFalse(CleanupService.isEligible(root.deletingLastPathComponent(), root: root))
    }

    func testRevalidatesFolderReplacedBySymlinkAfterScan() throws {
        let child = try folder("cache")
        let entries = try CleanupService.scan(root: root).entries
        try FileManager.default.removeItem(at: child)
        try FileManager.default.createSymbolicLink(at: child, withDestinationURL: root.deletingLastPathComponent())
        var called = false
        let result = CleanupService.moveToTrash(entries, root: root) { _ in called = true }
        XCTAssertFalse(called)
        XCTAssertEqual(result.moved, 0)
        XCTAssertEqual(result.failures.count, 1)
    }

    func testOnlySelectedEntriesMoveAndFailuresAreReported() throws {
        let first = try folder("first")
        let second = try folder("second")
        _ = try folder("unselected")
        let selected = try CleanupService.scan(root: root).entries.filter { $0.url.path == first.path || $0.url.path == second.path }
        var attempted: [URL] = []
        let result = CleanupService.moveToTrash(selected, root: root) { url in
            attempted.append(url)
            if url.path == second.path { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) }
        }
        XCTAssertEqual(Set(attempted.map(\.path)), Set([first.path, second.path]))
        XCTAssertEqual(result.moved, 1)
        XCTAssertEqual(result.failures.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("unselected").path))
    }
}
