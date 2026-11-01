import XCTest
@testable import MeuCleaner

final class StorageUXTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeuCleaner-UX-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func file(_ relative: String) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: 16_384).write(to: url)
        return url
    }
    private func finding(_ path: String, bytes: Int64, complete: Bool = true, disposition: StorageDisposition = .protected) -> StorageFinding {
        StorageFinding(url: root.appendingPathComponent(path), title: path, category: .userCaches,
                       measurement: StorageMeasurement(allocatedBytes: bytes, complete: complete),
                       disposition: disposition, reason: "test", sharedBlocks: false, identity: nil)
    }
    func testMapIncludesHiddenDirectoriesAndDoesNotFollowLinks() throws {
        _ = try file(".cache/hidden")
        _ = try file("Library/data")
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: root.appendingPathComponent("Library"))
        let (map, _) = SpaceLensScanner.scan(root)
        XCTAssertTrue(map.isComplete)
        XCTAssertTrue(map.children.contains { $0.name == ".cache" && $0.sizeBytes > 0 })
        XCTAssertEqual(map.children.first { $0.name == "alias" }?.sizeBytes, 0)
        XCTAssertEqual(map.sizeBytes, StorageMeter.measure(root).allocatedBytes)
    }
    func testBlockedReadTimesOutAndCannotAccumulateWorkersForTheSamePath() {
        let key = "test-blocked-read-\(UUID())"
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let started = Date()
        let first: Int? = BoundedFilesystemRead.run(key: key, timeout: 0.04) {
            gate.wait()
            return 42
        }
        XCTAssertNil(first)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        let duplicate: Int? = BoundedFilesystemRead.run(key: key, timeout: 0.04) { 7 }
        XCTAssertNil(duplicate, "A blocked read must retain its slot until the OS returns")
    }
    func testHardLinksAcrossSiblingsAreCountedOnce() throws {
        let original = try file("one/data")
        let linked = root.appendingPathComponent("two/data")
        try FileManager.default.createDirectory(at: linked.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.linkItem(at: original, to: linked)
        let map = SpaceLensScanner.scan(root).0
        XCTAssertEqual(map.sizeBytes, StorageMeter.measure(root).allocatedBytes)
    }
    func testMapBudgetAndMissingRootAreNotEmptySuccess() throws {
        _ = try file("present/data")
        let limited = SpaceLensScanner.scan(root, timeLimit: 0).0
        XCTAssertFalse(limited.isComplete)
        XCTAssertFalse(limited.children.isEmpty)
        XCTAssertFalse(limited.issues.isEmpty)
        let missing = SpaceLensScanner.scan(root.appendingPathComponent("missing")).0
        XCTAssertFalse(missing.isComplete)
    }
    func testParentInventoryDoesNotDoubleCountChildren() {
        var report = StorageReport()
        report.findings = [finding("Claude/Cache", bytes: 25), finding("Claude", bytes: 100), finding("Other", bytes: 20)]
        XCTAssertEqual(report.largestLocations.count, 2)
        XCTAssertEqual(report.largestLocations.reduce(0) { $0 + $1.measurement.allocatedBytes }, 120)
    }
    func testPartialParentDoesNotHideMeasuredChildren() {
        var report = StorageReport()
        report.findings = [finding("Claude", bytes: 0, complete: false), finding("Claude/Cache", bytes: 25)]
        XCTAssertEqual(report.largestLocations.map(\.title), ["Claude/Cache"])
    }
    func testPartialProtectedMeasurementHasOnlyUnknownGroup() {
        let item = finding("blocked", bytes: 0, complete: false)
        XCTAssertEqual(ReviewGroup.allCases.filter { $0.contains(item) }, [.unknown])
        XCTAssertFalse(item.canReviewRemoval)
        XCTAssertEqual(item.statusLabel, "Leitura parcial")
    }
    func testKnownEmptyAndAbsentAreDifferent() throws {
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        var scanner = IntelligentStorageScanner(home: root, cloneRoot: root, usage: FileUsageSnapshot())
        XCTAssertTrue(scanner.children(empty).isEmpty)
        XCTAssertTrue(scanner.children(root.appendingPathComponent("missing")).isEmpty)
        XCTAssertEqual(scanner.report.locationChecks.map(\.state), [.empty, .absent])
    }
    func testInternalCachesRemainBlockedWhileOwnerRuns() throws {
        let cache = try file("Library/Application Support/Claude/Cache/data").deletingLastPathComponent()
        let usage = FileUsageSnapshot(executablePaths: ["/Applications/Claude.app/Contents/MacOS/Claude"])
        var scanner = IntelligentStorageScanner(home: root, cloneRoot: root, usage: usage)
        scanner.append(cache, title: "Cache do Claude", category: .userCaches)
        XCTAssertEqual(scanner.report.findings.first?.disposition, .inUse)
        XCTAssertFalse(scanner.report.findings.first!.canReviewRemoval)
    }
    func testHistoryPersistsPartialResultsAndDestination() throws {
        let entry = CleanupActivity(title: "Arquivos", destination: "Destino: Lixeira", rows: [
            CleanupResultRow(id: "a", title: "Cache", success: true, message: "Movido para a Lixeira"),
            CleanupResultRow(id: "b", title: "Banco", success: false, message: "Preservado")
        ], freeBefore: 10, freeAfter: 10, note: "Espaço ainda ocupado")
        let restored = try JSONDecoder().decode(CleanupActivity.self, from: JSONEncoder().encode(entry))
        XCTAssertEqual(restored.destination, entry.destination)
        XCTAssertEqual(restored.rows.filter(\.success).count, 1)
        XCTAssertNil(restored.restoredAt)
    }
    @MainActor
    func testDuplicatesCannotSelectOrReviewEveryCopy() async throws {
        let first = try file("duplicates/first")
        let second = try file("duplicates/second")
        let scanner = DiskScannerService()
        let group = DuplicateGroup(hashHex: "fixture", eachFileSizeBytes: 16_384, files: [
            DuplicateFileEntry(url: first, name: "first", modifiedDate: Date(), isSelectedForRemoval: false),
            DuplicateFileEntry(url: second, name: "second", modifiedDate: Date(), isSelectedForRemoval: false)
        ])
        scanner.duplicateGroups = [group]
        scanner.setDuplicateSelection(groupID: group.id, fileID: group.files[0].id, selected: true)
        scanner.setDuplicateSelection(groupID: group.id, fileID: group.files[1].id, selected: true)
        XCTAssertEqual(scanner.duplicateGroups[0].files.filter(\.isSelectedForRemoval).count, 1)
        scanner.duplicateGroups[0].files[1].isSelectedForRemoval = true
        _ = await scanner.cleanSelectedDuplicates()
        XCTAssertNil(scanner.cleanupRequest)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
    }
    @MainActor
    func testPreparingReviewNeverRemovesFilesOrCreatesCleanupHistory() async throws {
        let url = try file("chosen/data")
        let scanner = DiskScannerService()
        let previousCount = scanner.cleanupActivities.count
        await scanner.prepareFileReview([url], title: "Revisão de teste", consequence: "Arquivo escolhido")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try Data(contentsOf: url).count, 16_384)
        XCTAssertEqual(scanner.cleanupActivities.count, previousCount)
        XCTAssertNotNil(scanner.cleanupRequest)
        XCTAssertFalse(scanner.isScanningJunk)
    }
}
