import XCTest
@testable import MeuCleaner

final class MeuCleanerTests: XCTestCase {
    func testSafetyGuardBlocksSystemAndProtectedUserPaths() {
        let forbiddenURLs: [URL] = [
            URL(fileURLWithPath: "/System/Library"),
            URL(fileURLWithPath: "/usr/bin"),
            URL(fileURLWithPath: "/Users/Shared"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Documents/Relatorio.pdf"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Library/Keychains/login.keychain-db"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Library/CloudStorage/GoogleDrive"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Pictures/Photos Library.photoslibrary")
        ]

        for url in forbiddenURLs {
            XCTAssertThrowsError(try SafetyGuard.validateCanMoveToTrash(url), "Deveria bloquear caminho protegido: \(url.path)")
        }
    }

    func testSafetyGuardAllowsUserCachesAndThirdPartyAppBundles() {
        let safeCacheURL = SafetyGuard.homeDirectoryURL.appendingPathComponent("Library/Caches/com.example.testcache")
        XCTAssertNoThrow(try SafetyGuard.validateCanMoveToTrash(safeCacheURL))

        let thirdPartyApp = URL(fileURLWithPath: "/Applications/ExampleThirdParty.app")
        XCTAssertNoThrow(try SafetyGuard.validateCanMoveToTrash(thirdPartyApp))
    }

    func testRunningAppsAndDotCacheComeUncheckedByDefault() {
        let openAppJunk = JunkItem(
            url: URL(fileURLWithPath: "/tmp/cache1"),
            name: "com.running.app",
            category: .userCaches,
            sizeBytes: 1024,
            isRunningApp: true
        )
        XCTAssertFalse(openAppJunk.isSelected, "Caches de apps abertos devem vir desmarcados por padrão")
        XCTAssertEqual(openAppJunk.note, "App aberto")

        let dotCacheJunk = JunkItem(
            url: URL(fileURLWithPath: "/tmp/.cache/huggingface"),
            name: "~/.cache/huggingface",
            category: .dotCache,
            sizeBytes: 2048,
            isRunningApp: false
        )
        XCTAssertFalse(dotCacheJunk.isSelected, "~/.cache deve vir desmarcado por padrão para revisão")
        XCTAssertEqual(dotCacheJunk.note, "Revisar")

        let closedAppJunk = JunkItem(
            url: URL(fileURLWithPath: "/tmp/cache2"),
            name: "com.closed.app",
            category: .userCaches,
            sizeBytes: 1024,
            isRunningApp: false
        )
        XCTAssertTrue(closedAppJunk.isSelected)
    }

    func testLeftoversComeUncheckedByDefault() {
        let group = OrphanedLeftoverGroup(
            inferredAppName: "OldApp",
            identifierHint: "com.old.app",
            files: []
        )
        XCTAssertFalse(group.isSelected, "Restos de apps na Library nunca devem vir marcados por padrão")
    }

    func testSemanticVersionComparison() {
        XCTAssertTrue(AppVersion.isNewer("1.2.1", than: "1.2.0"))
        XCTAssertTrue(AppVersion.isNewer("2.0", than: "1.9.9"))
        XCTAssertFalse(AppVersion.isNewer("1.2.0", than: "1.2.0"))
        XCTAssertFalse(AppVersion.isNewer("1.1.9", than: "1.2.0"))
    }
}
