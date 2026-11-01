import XCTest
@testable import MeuCleaner

final class ReviewedCleanupTests: XCTestCase {
    private let imageID = "sha256:" + String(repeating: "a", count: 64)
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    private var image: DockerImageCandidate { .init(id: imageID, names: ["postgres:16"], size: 100, containers: 0) }
    private var inventory: DockerInventory { .init(socket: "/tmp/test.sock", daemonID: "local-engine", images: [image], caches: []) }

    func testActualSafetyGuardPreservesOpenFixtureAndRemovesItOnlyAfterClose() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/MeuCleaner-SafetyTest-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("disposable-test-payload")
        try Data(repeating: 42, count: 8192).write(to: file)
        let identity = try XCTUnwrap(FileIdentity.read(file))
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        XCTAssertThrowsError(try SafetyGuard.remove(file, mode: .permanent, expectedIdentity: identity))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        try handle.close()
        _ = try SafetyGuard.remove(file, mode: .permanent, expectedIdentity: identity)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testStorageHistoryPersistsBaselineWithoutClaimingNewPathsGrew() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("snapshot.json")
        var first = StorageReport()
        first.findings = [.init(url: URL(fileURLWithPath: "/fixture"), title: "Fixture", category: nil,
                                measurement: .init(allocatedBytes: 100), disposition: .protected, reason: "", sharedBlocks: false, identity: nil)]
        XCTAssertNil(StorageHistory.update(first, at: path).0)
        var next = StorageReport()
        next.findings = [.init(url: URL(fileURLWithPath: "/fixture"), title: "Fixture", category: nil,
                               measurement: .init(allocatedBytes: 300), disposition: .protected, reason: "", sharedBlocks: false, identity: nil)]
        let result = StorageHistory.update(next, at: path)
        XCTAssertNotNil(result.0); XCTAssertNil(result.2)
        XCTAssertEqual(result.1.first?.delta, 200)
    }

    func testRemoteOrUnexpectedDockerEndpointsAreRejected() {
        XCTAssertNil(DockerMaintenance.validatedSocket("tcp://server:2375"))
        XCTAssertNil(DockerMaintenance.validatedSocket("ssh://server"))
        XCTAssertNil(DockerMaintenance.validatedSocket("unix:///tmp/unexpected.sock"))
        XCTAssertNotNil(DockerMaintenance.validatedSocket("unix:///var/run/docker.sock"))
    }
    func testImageBecomingUsedByStoppedContainerIsPreserved() throws {
        var mutations = 0
        let client = DockerMaintenance(socket: inventory.socket) { _, method, route in
            if method != "GET" { mutations += 1 }
            if route == "/info" { return try self.json(["ID": "local-engine"]) }
            if route.hasPrefix("/images/") { return try self.json(["Id": self.imageID, "RepoTags": ["postgres:16"]]) }
            XCTAssertTrue(route.contains("all=1"))
            return try self.json([["Id": "stopped", "State": "exited"]])
        }
        XCTAssertThrowsError(try client.removeImage(image, expected: inventory))
        XCTAssertEqual(mutations, 0)
    }
    func testImageRemovalIsPinnedToIDAndNeverForcedOrPrunesParents() throws {
        var deleted = false
        let client = DockerMaintenance(socket: inventory.socket) { _, method, route in
            if route == "/info" { return try self.json(["ID": "local-engine"]) }
            if method == "DELETE" {
                XCTAssertTrue(route.hasPrefix("/images/" + self.imageID))
                XCTAssertTrue(route.contains("force=false")); XCTAssertTrue(route.contains("noprune=true"))
                deleted = true; return try self.json([["Deleted": self.imageID]])
            }
            if route.hasPrefix("/images/") { return try self.json(["Id": self.imageID, "RepoTags": ["postgres:16"]]) }
            return try self.json([])
        }
        _ = try client.removeImage(image, expected: inventory)
        XCTAssertTrue(deleted)
    }
    func testChangedDockerDaemonOrImageTagsBlocksDeletion() throws {
        for changedDaemon in [true, false] {
            var mutations = 0
            let client = DockerMaintenance(socket: inventory.socket) { _, method, route in
                if method != "GET" { mutations += 1 }
                if route == "/info" { return try self.json(["ID": changedDaemon ? "other-engine" : "local-engine"]) }
                return try self.json(["Id": self.imageID, "RepoTags": ["new:tag"]])
            }
            XCTAssertThrowsError(try client.removeImage(image, expected: inventory)); XCTAssertEqual(mutations, 0)
        }
    }
    func testBuildCachePruneOnlyTargetsReviewedIDsStillOldAndUnused() throws {
        let old = Date(timeIntervalSinceNow: -172800)
        let prior = DockerInventory(socket: inventory.socket, daemonID: "local-engine", images: [], caches: [
            .init(id: "eligible", inUse: false, lastUsed: old), .init(id: "became-used", inUse: false, lastUsed: old)])
        var posted = false
        let client = DockerMaintenance(socket: inventory.socket) { _, method, route in
            if route == "/info" { return try self.json(["ID": "local-engine"]) }
            if route == "/system/df" {
                return try self.json(["Images": [], "BuildCache": [
                    ["ID": "eligible", "InUse": false, "LastUsedAt": ISO8601DateFormatter().string(from: old)],
                    ["ID": "became-used", "InUse": true, "LastUsedAt": ISO8601DateFormatter().string(from: old)],
                    ["ID": "new-unreviewed", "InUse": false, "LastUsedAt": ISO8601DateFormatter().string(from: old)]]])
            }
            XCTAssertEqual(method, "POST"); XCTAssertTrue(route.hasPrefix("/build/prune?"))
            let query = try XCTUnwrap(URLComponents(string: route)?.queryItems)
            XCTAssertEqual(query.first { $0.name == "all" }?.value, "false")
            let filter = try XCTUnwrap(query.first { $0.name == "filters" }?.value?.data(using: .utf8))
            let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: filter) as? [String: [String]])
            XCTAssertEqual(decoded["id"], ["eligible"]); XCTAssertEqual(decoded["until"], ["24h"])
            XCTAssertEqual(decoded["inuse"], ["false"])
            posted = true; return try self.json(["CachesDeleted": ["eligible"], "SpaceReclaimed": 4096])
        }
        _ = try client.pruneCache(expected: prior)
        XCTAssertTrue(posted)
    }
    func testChromeIsVisibleButSharedBytesNeverBecomeGuaranteedGain() {
        let finding = StorageFinding(url: URL(fileURLWithPath: "/tmp/code_sign_clone.ABC123"), title: "Chrome", category: .browserClones,
                                     measurement: .init(allocatedBytes: 2_000_000), disposition: .review, reason: "APFS", sharedBlocks: true, identity: nil)
        var report = StorageReport(); report.findings = [finding]
        XCTAssertEqual(report.findings(in: .chrome).count, 1)
        XCTAssertEqual(report.candidateMeasuredBytes, 0)
        XCTAssertFalse(finding.canReviewRemoval, "Missing identity must block removal even if disposition permits review")
    }
    func testGrowthSkipsNewPathsPartialReadsAndSharedClones() {
        func item(_ path: String, bytes: Int64, complete: Bool = true, shared: Bool = false) -> StorageFinding {
            StorageFinding(url: URL(fileURLWithPath: path), title: path, category: .userCaches,
                           measurement: .init(allocatedBytes: bytes, complete: complete), disposition: .review, reason: "", sharedBlocks: shared, identity: nil)
        }
        var before = StorageReport(); before.findings = [item("/cache", bytes: 100), item("/partial", bytes: 100), item("/clone", bytes: 100, shared: true)]
        var after = StorageReport(); after.findings = [item("/cache", bytes: 150), item("/partial", bytes: 500, complete: false), item("/clone", bytes: 1000, shared: true), item("/new", bytes: 500)]
        let changes = StorageSnapshot(report: before).growth(in: after)
        XCTAssertEqual(changes.count, 1); XCTAssertEqual(changes[0].id, "/cache"); XCTAssertEqual(changes[0].delta, 50)
    }
}
