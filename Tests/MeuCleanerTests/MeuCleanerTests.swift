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

        // Prefix "v" normalization
        XCTAssertTrue(AppVersion.isNewer("v1.2.0", than: "1.1.0"))
        XCTAssertFalse(AppVersion.isNewer("v1.1.0", than: "1.2.0"))
        XCTAssertEqual(AppVersion.normalize(" v2.3.4 \n"), "2.3.4")
    }

    func testSafetyGuardBlocksCredentialsAndEnvFiles() {
        let credentialURLs: [URL] = [
            SafetyGuard.homeDirectoryURL.appendingPathComponent(".ssh/id_rsa"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent(".ssh/authorized_keys"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent(".aws/credentials"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent(".gnupg/secring.gpg"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Projects/MyProject/.env"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Projects/MyProject/.env.local"),
            SafetyGuard.homeDirectoryURL.appendingPathComponent("Projects/MyProject/.env.production")
        ]

        for url in credentialURLs {
            XCTAssertThrowsError(try SafetyGuard.validateCanMoveToTrash(url), "Deveria bloquear arquivo/pasta sensível de credencial: \(url.path)")
        }
    }

    @MainActor
    func testSelfUpdaterServiceInitialization() {
        let updater = SelfUpdaterService()
        XCTAssertFalse(updater.isChecking)
        XCTAssertFalse(updater.isDownloading)
        XCTAssertNil(updater.availableUpdate)
        XCTAssertEqual(SelfUpdaterService.repositoryOwner, "vagneralencar")
        XCTAssertEqual(SelfUpdaterService.repositoryName, "MeuCleaner-Mac")
    }

    func testDevArtifactSelectionRules() {
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: Date()) ?? Date()
        let oldNodeModules = DevArtifactItem(
            url: URL(fileURLWithPath: "/tmp/proj/node_modules"),
            projectName: "proj",
            artifactFolderName: "node_modules",
            category: .nodeModules,
            sizeBytes: 100_000_000,
            lastModified: fortyDaysAgo
        )
        XCTAssertTrue(oldNodeModules.isSelected, "node_modules inativo há > 30 dias deve vir pré-marcado")

        let aiModel = DevArtifactItem(
            url: URL(fileURLWithPath: "/tmp/.ollama/models"),
            projectName: "Ollama",
            artifactFolderName: "models",
            category: .aiModels,
            sizeBytes: 4_000_000_000,
            lastModified: fortyDaysAgo
        )
        XCTAssertFalse(aiModel.isSelected, "Modelos de IA nunca devem vir pré-marcados automaticamente")
    }

    func testDuplicateGroupReclaimableCalculation() {
        let group = DuplicateGroup(
            hashHex: "abc123def456",
            eachFileSizeBytes: 10_000_000,
            files: [
                DuplicateFileEntry(url: URL(fileURLWithPath: "/tmp/a.dmg"), name: "a.dmg", modifiedDate: Date(), isSelectedForRemoval: false),
                DuplicateFileEntry(url: URL(fileURLWithPath: "/tmp/b.dmg"), name: "b.dmg", modifiedDate: Date(), isSelectedForRemoval: true),
                DuplicateFileEntry(url: URL(fileURLWithPath: "/tmp/c.dmg"), name: "c.dmg", modifiedDate: Date(), isSelectedForRemoval: true)
            ]
        )
        XCTAssertEqual(group.maxReclaimableBytes, 20_000_000)
        XCTAssertEqual(group.selectedReclaimableBytes, 20_000_000)
    }
}
