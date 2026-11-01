import XCTest
@testable import MeuCleaner

final class StorageInspectionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("MeuCleaner-tests-\(UUID())").resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    private func file(_ relative: String, bytes: Int = 8192) throws -> URL {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 42, count: bytes).write(to: url)
        return url
    }
    private func available(openPaths: Set<String> = []) -> FileUsageSnapshot {
        FileUsageSnapshot(openPaths: openPaths, executablePaths: [], mountedPaths: [], issues: [])
    }

    func testDeepHiddenFilesAndHardLinksAreMeasuredOnce() throws {
        let first = try file(".hidden/a/b/c/d/e/f/payload")
        try FileManager.default.linkItem(at: first, to: root.appendingPathComponent("hardlink"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("cycle").path, withDestinationPath: root.path)
        let result = StorageMeter.measure(root)
        XCTAssertTrue(result.complete)
        XCTAssertEqual(result.logicalBytes, 8192)
        XCTAssertGreaterThanOrEqual(result.allocatedBytes, 8192)
    }

    func testFrameworkSymlinksDoNotSkipRealVersionDirectories() throws {
        let framework = root.appendingPathComponent("App.app/Contents/Frameworks/Example.framework")
        try FileManager.default.createDirectory(at: framework, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Example").path, withDestinationPath: "Versions/Current/Example")
        try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Resources").path, withDestinationPath: "Versions/Current/Resources")
        _ = try file("App.app/Contents/Frameworks/Example.framework/Versions/A/Example")
        _ = try file("App.app/Contents/Frameworks/Example.framework/Versions/B/Example")
        try FileManager.default.createSymbolicLink(atPath: framework.appendingPathComponent("Versions/Current").path, withDestinationPath: "A")
        let measurement = StorageMeter.measure(root)
        XCTAssertTrue(measurement.complete)
        XCTAssertEqual(measurement.logicalBytes, 16384)
    }

    func testReadLimitIsPartialInsteadOfZeroOrSafe() throws {
        _ = try file("a"); _ = try file("b")
        let measured = StorageMeter.measure(root, maxEntries: 1)
        XCTAssertFalse(measured.complete)
        XCTAssertFalse(measured.issues.isEmpty)
        XCTAssertFalse(StorageMeter.measure(root.appendingPathComponent("missing")).complete)
    }

    func testGitWorktreeFileAndNestedRepositoryAreProtected() throws {
        let marker = try file("project/.git", bytes: 30)
        let build = try file("project/.build/result")
        XCTAssertEqual(StoragePaths.repositoryAncestor(of: build), marker.deletingLastPathComponent())
        XCTAssertTrue(StorageMeter.measure(root).containsProtectedContent)
        try FileManager.default.removeItem(at: marker)
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        XCTAssertNotNil(StoragePaths.repositoryAncestor(of: build))
    }

    func testSensitiveContentCannotBeHiddenInsideParentFolder() throws {
        _ = try file("cache/subfolder/.env.production")
        XCTAssertTrue(StorageMeter.measure(root.appendingPathComponent("cache")).containsProtectedContent)
        XCTAssertThrowsError(try SafetyGuard.validateCanMoveToTrash(SafetyGuard.homeDirectoryURL.appendingPathComponent("Library")))
        XCTAssertThrowsError(try SafetyGuard.validateCanMoveToTrash(SafetyGuard.homeDirectoryURL.appendingPathComponent(".ssh/subfolder")))
    }

    func testProtectedRuntimeDataCannotBeDeletedByAnotherChannel() {
        for path in ["Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", "Library/Developer/CoreSimulator/Devices/device", ".android/avd/emulator.avd", "Library/Developer/Xcode/Archives/archive", "Library/Application Support/Claude/vm_bundles"] {
            XCTAssertThrowsError(try SafetyGuard.validateCanMoveToTrash(SafetyGuard.homeDirectoryURL.appendingPathComponent(path)))
        }
    }

    func testOpenDescendantBlocksParentButNotSiblingPrefix() throws {
        let open = try file("cache/a")
        let snapshot = available(openPaths: [open.path])
        XCTAssertNotNil(snapshot.blocker(for: root.appendingPathComponent("cache")))
        XCTAssertNil(snapshot.blocker(for: root.appendingPathComponent("cache-other")))
    }

    func testMountedImagesAndProcessesArePreserved() {
        var snapshot = available()
        snapshot.mountedPaths = [root.appendingPathComponent("installer.dmg").path]
        XCTAssertNotNil(snapshot.blocker(for: root))
        snapshot.mountedPaths = []
        snapshot.executablePaths = ["/Applications/Xcode.app/Contents/MacOS/Xcode"]
        XCTAssertNotNil(snapshot.blocker(for: URL(fileURLWithPath: "/Users/test/Library/Developer/Xcode/DerivedData/app")))
        snapshot.executablePaths = ["/opt/jdk/bin/java"]
        XCTAssertNotNil(snapshot.blocker(for: URL(fileURLWithPath: "/Users/test/.gradle/caches")))
    }

    func testFailedOrPartialLsofBlocksCleanup() {
        let plist = "<?xml version=\"1.0\"?><plist version=\"1.0\"><dict><key>images</key><array/></dict></plist>"
        let processes = InspectionCommandResult(output: "/usr/bin/tool\n", exitCode: 0)
        let mounts = InspectionCommandResult(output: plist, exitCode: 0)
        for files in [InspectionCommandResult(error: "denied"), InspectionCommandResult(output: "p1\0n/tmp/a\0", error: "partial", exitCode: 0), InspectionCommandResult(output: "truncated", exitCode: 0)] {
            let snapshot = FileUsageSnapshot.parse(files: files, processes: processes, mounts: mounts)
            XCTAssertFalse(snapshot.verified)
            XCTAssertNotNil(snapshot.blocker(for: root))
        }
        let snapshot = FileUsageSnapshot.parse(files: InspectionCommandResult(output: "p1\0ctool\0n/tmp/a\0\np2\0n/tmp/b\0", exitCode: 0), processes: processes, mounts: mounts)
        XCTAssertTrue(snapshot.verified)
        XCTAssertEqual(snapshot.openPaths.count, 2)
    }

    func testChromeAllowlistRejectsSiblingsSymlinksAndWrongBundles() throws {
        let cloneRoot = root.appendingPathComponent("X/com.google.Chrome.code_sign_clone")
        let clone = cloneRoot.appendingPathComponent("code_sign_clone.Ab12XY")
        let plist = clone.appendingPathComponent("Google Chrome.app.bundle/Contents/Info.plist")
        try FileManager.default.createDirectory(at: plist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.google.Chrome"], format: .xml, options: 0).write(to: plist)
        XCTAssertTrue(ChromeClonePolicy.isValid(clone, root: cloneRoot))
        XCTAssertFalse(ChromeClonePolicy.isValid(cloneRoot, root: cloneRoot))
        XCTAssertFalse(ChromeClonePolicy.isValid(root, root: cloneRoot))
        let alias = cloneRoot.appendingPathComponent("code_sign_clone.ZZ12XY")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: clone)
        XCTAssertFalse(ChromeClonePolicy.isValid(alias, root: cloneRoot))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "other.app"], format: .xml, options: 0).write(to: plist)
        XCTAssertFalse(ChromeClonePolicy.isValid(clone, root: cloneRoot))
    }

    func testAPFSClonesAndInventoryNeverInflateCandidateTotal() {
        let measurement = StorageMeasurement(allocatedBytes: 71_000_000_000, logicalBytes: 71_000_000_000)
        var report = StorageReport()
        report.findings = [StorageFinding(url: root, title: "Chrome", category: .browserClones, measurement: measurement, disposition: .review, reason: "Shared", sharedBlocks: true, identity: nil)]
        XCTAssertEqual(report.candidateMeasuredBytes, 0)
        XCTAssertFalse(report.junkItems[0].isSelected)
        XCTAssertTrue(report.junkItems[0].canClean)
    }

    func testUnverifiedScannerDoesNotSelectCandidates() throws {
        let cache = try file("Library/Caches/tool/payload")
        var scanner = IntelligentStorageScanner(home: root, usage: FileUsageSnapshot(issues: ["lsof unavailable"]))
        scanner.append(cache.deletingLastPathComponent(), title: "tool", category: .userCaches)
        XCTAssertEqual(scanner.report.findings.first?.disposition, .unverified)
        XCTAssertFalse(scanner.report.junkItems[0].canClean)
        XCTAssertFalse(scanner.report.junkItems[0].isSelected)
    }

    func testFileIdentityChangesWhenScanTargetIsReplaced() throws {
        let url = try file("target")
        let original = FileIdentity.read(url)
        try FileManager.default.moveItem(at: url, to: root.appendingPathComponent("old"))
        _ = try file("target")
        XCTAssertNotEqual(original, FileIdentity.read(url))
    }

    func testDockerJSONAndFailureDoNotConfuseUnknownWithZero() {
        let payload = "{\"Type\":\"Local Volumes\",\"TotalCount\":46,\"Active\":4,\"Size\":\"13.04GB\",\"Reclaimable\":\"7.818GB (59%)\"}"
        let rows = IntelligentStorageScanner.parseDocker(payload)
        XCTAssertEqual(rows?.first?.count, "46")
        XCTAssertEqual(rows?.first?.reclaimable, "7.818GB (59%)")
        XCTAssertNil(IntelligentStorageScanner.parseDocker("Cannot connect to Docker"))
        XCTAssertNil(IntelligentStorageScanner.parseDocker(""))
        XCTAssertNil(IntelligentStorageScanner.parseDocker(payload + "\npartial"))
    }

    func testCommandRunnerDrainsLargeOutputAndTimesOut() {
        let output = InspectionCommand.run("/usr/bin/yes", ["test"], timeout: 0.1)
        XCTAssertTrue(output.timedOut)
        XCTAssertFalse(output.succeeded)
        let ok = InspectionCommand.run("/usr/bin/printf", ["hello"])
        XCTAssertTrue(ok.succeeded)
        XCTAssertEqual(ok.output, "hello")
    }

    func testRuntimeInventoryDoesNotTreatMissingMetadataAsZero() {
        let json = "{\"runtime-id\":{\"version\":\"27.0\",\"sizeBytes\":8067000161,\"lastUsedAt\":\"2026-11-01T03:55:57Z\"}}"
        XCTAssertEqual(IntelligentStorageScanner.parseSimulatorRuntimes(json)?.first?.sizeBytes, 8067000161)
        XCTAssertEqual(IntelligentStorageScanner.parseSimulatorRuntimes("{}")?.count, 0)
        XCTAssertNil(IntelligentStorageScanner.parseSimulatorRuntimes("{\"runtime-id\":{\"version\":\"27.0\"}}"))
        XCTAssertNil(IntelligentStorageScanner.parseSimulatorRuntimes("error"))
    }

    func testToolVersionPointerIsRecheckedAndUnknownVersionsArePreserved() throws {
        let old = try file("versions/1.0.0")
        let current = try file("versions/2.0.0")
        let newer = try file("versions/3.0.0")
        let link = root.appendingPathComponent("current")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: current)
        let store = ToolVersionStore(root: old.deletingLastPathComponent(), currentLink: link, title: "test")
        XCTAssertTrue(store.isOldEntry(old))
        XCTAssertFalse(store.isOldEntry(current))
        XCTAssertFalse(store.isOldEntry(newer))
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: old)
        XCTAssertFalse(store.isOldEntry(old), "An item that became current must no longer be removable")
        try FileManager.default.removeItem(at: link)
        XCTAssertFalse(store.isOldEntry(current))
    }

    func testOpenAppCacheIsPreservedEvenBetweenFileReads() {
        var snapshot = available()
        snapshot.applicationIdentifiers = ["com.example.app"]
        XCTAssertNotNil(snapshot.blocker(for: URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.app/Cache")))
        XCTAssertNil(snapshot.blocker(for: URL(fileURLWithPath: "/Users/test/Library/Caches/com.example.application")))
    }

    func testBoundedDirectoryListingPreservesNamesAndReportsMissingPaths() throws {
        let first = try file("file with spaces")
        let second = try file("file\nwith newline")
        let listing = StorageDirectory.list(root)
        XCTAssertNil(listing.issue)
        XCTAssertEqual(Set(listing.urls), [first, second])
        XCTAssertNotNil(StorageDirectory.list(root.appendingPathComponent("missing")).issue)
    }

    func testProtectedInventoriesRemainVisibleOutsideCleanupList() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var report = StorageReport()
        for (path, group) in [("Library/Containers/com.docker.docker/Data", StorageEnvironment.docker), ("Library/Developer/Xcode/Archives", .xcode), (".android/avd", .android)] {
            let item = StorageFinding(url: home.appendingPathComponent(path), title: path, category: nil,
                                      measurement: StorageMeasurement(allocatedBytes: 8192), disposition: .protected,
                                      reason: "Preservado", sharedBlocks: false, identity: nil)
            report.findings.append(item)
            XCTAssertEqual(report.findings(in: group).map(\.id), [item.id])
        }
        XCTAssertTrue(report.junkItems.isEmpty)
        XCTAssertEqual(report.candidateMeasuredBytes, 0)
        let unrelated = StorageFinding(url: home.appendingPathComponent("dev/android-app"), title: "Projeto", category: nil,
                                       measurement: StorageMeasurement(allocatedBytes: 8192), disposition: .protected,
                                       reason: "Preservado", sharedBlocks: false, identity: nil)
        XCTAssertNil(StorageEnvironment.classify(unrelated))
    }

    func testZeroDockerBuildCacheIsShownInsteadOfOmitted() throws {
        let rows = try XCTUnwrap(IntelligentStorageScanner.parseDocker(#"{"Type":"Build Cache","Size":"0B","Reclaimable":"0B","TotalCount":0,"Active":0}"#))
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].displayName, "Cache de builds")
        XCTAssertEqual(rows[0].size, "0B")
    }

    func testLiveReadOnlyScanWhenExplicitlyEnabled() throws {
        guard ProcessInfo.processInfo.environment["MEUCLEANER_LIVE_SCAN"] == "1" else { throw XCTSkip("Opt-in read-only integration scan") }
        let report = IntelligentStorageScanner.scan()
        print("LIVE_SCAN findings=\(report.findings.count) clones=\(report.findings.filter { $0.sharedBlocks }.count) dockerRows=\(report.dockerRows.count) issues=\(report.issues.count) free=\(report.freeBytes)")
        print("LIVE_ISSUES \(report.issues)")
        if let clone = report.findings.first(where: { $0.sharedBlocks }) {
            let disk = InspectionCommand.run("/usr/bin/du", ["-sk", clone.url.path], timeout: 15)
            let kib = disk.output.split(whereSeparator: \.isWhitespace).first.flatMap { Int64($0) }
            XCTAssertTrue(disk.succeeded)
            XCTAssertEqual(clone.measurement.allocatedBytes, try XCTUnwrap(kib) * 1024)
            print("LIVE_CLONE_MEASUREMENT allocated=\(clone.measurement.allocatedBytes) matches_du=true")
        }
        // This opt-in smoke test also runs on Macs with Docker stopped or absent.
        // Unavailable must be reported explicitly, never as a successful zero-sized inventory.
        XCTAssertNotEqual(report.dockerNote, "Docker ainda não consultado.")
        if report.dockerInventory != nil {
            XCTAssertFalse(report.dockerRows.isEmpty)
        } else if !report.dockerRows.isEmpty {
            XCTAssertTrue(report.issues.contains { $0.hasPrefix("Limpeza Docker bloqueada:") })
        } else {
            XCTAssertTrue(report.dockerNote.contains("indisponível") || report.dockerNote.contains("não encontrado"))
        }
        print("LIVE_DOCKER unusedImages=\(report.dockerInventory?.images.filter(\.canRemove).count ?? -1)")
        XCTAssertGreaterThan(report.findings.count, 0)
        XCTAssertGreaterThan(report.freeBytes, 0)
        XCTAssertFalse(report.junkItems.contains { $0.isSelected && !$0.canClean })
    }
}
