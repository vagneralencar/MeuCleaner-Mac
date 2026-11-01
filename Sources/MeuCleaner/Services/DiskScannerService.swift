import Foundation
import AppKit

@MainActor
public final class DiskScannerService: ObservableObject {
    // User preference: Trash (default) vs Permanent deletion
    @Published public var removalMode: RemovalMode = .trash

    // Channel 00 & 01: System Junk
    @Published public var junkItems: [JunkItem] = []
    @Published public var isScanningJunk: Bool = false
    @Published var storageReport = StorageReport()
    @Published var cleanupRequest: CleanupRequest?
    @Published var cleanupProgress = ""
    @Published var storageGrowth: [StorageGrowth] = []
    @Published var previousScanDate: Date?
    @Published public var isCleaningJunk = false
    @Published public var lastScanDurationSeconds: Double?

    // Channel 02: Space Lens
    @Published public var spaceLensRoot: DiskNode?
    @Published public var spaceLensBreadcrumbs: [DiskNode] = []
    @Published public var isScanningSpaceLens: Bool = false
    @Published public var spaceLensScannedItemsCount: Int = 0

    // Channel 03: Large & Old
    @Published public var largeFiles: [LargeFileItem] = []
    @Published public var isScanningLargeFiles: Bool = false

    // Channel 04: Uninstaller
    @Published public var installedApps: [InstalledApp] = []
    @Published public var isScanningApps: Bool = false

    // Channel 05: Leftovers
    @Published public var leftoverGroups: [OrphanedLeftoverGroup] = []
    @Published public var isScanningLeftovers: Bool = false

    // Channel 06: Trash
    @Published public var trashItems: [TrashItem] = []
    @Published public var isScanningTrash: Bool = false
    @Published var hasScannedTrash = false

    // Channel 07: App Updater
    @Published public var updatableApps: [UpdatableApp] = []
    @Published public var isScanningUpdates: Bool = false
    @Published public var updatingAppIDs: Set<UUID> = []

    // Channel 08: Dev & IA Cleaner
    @Published public var devArtifacts: [DevArtifactItem] = []
    @Published public var isScanningDevArtifacts: Bool = false

    // Channel 09: Startup & LaunchAgents
    @Published public var startupAgents: [StartupAgentItem] = []
    @Published public var isScanningStartupAgents: Bool = false

    // Channel 10: Smart Duplicates
    @Published public var duplicateGroups: [DuplicateGroup] = []
    @Published public var isScanningDuplicates: Bool = false

    // Vigia da Lixeira (Trash App Watcher) & History
    @Published public var trashedAppAlerts: [TrashedAppAlert] = []
    @Published public var trashWatcherEnabled: Bool = true
    @Published public var cleanupHistory: [CleanupHistoryRecord] = []
    @Published public var lastTrashReceipts: [TrashReceipt] = []

    // Status Banner / Feedback
    @Published public var lastStatusMessage: String?
    @Published public var hasFullDiskAccess: Bool = SafetyGuard.hasFullDiskAccess()

    private static let historyDefaultsKey = "MeuCleaner.CleanupHistory.v1"

    public init() {
        loadCleanupHistory()
    }

    public func refreshFullDiskAccessStatus() {
        hasFullDiskAccess = SafetyGuard.hasFullDiskAccess()
    }

    public var totalLifetimeFreedBytes: Int64 {
        cleanupHistory.reduce(0) { $0 + $1.freedBytes }
    }

    public func recordCleanupHistory(channelTitle: String, freedBytes: Int64, itemsCount: Int) {
        guard freedBytes > 0 else { return }
        let entry = CleanupHistoryRecord(
            channelTitle: channelTitle,
            freedBytes: freedBytes,
            itemsCount: max(1, itemsCount)
        )
        cleanupHistory.insert(entry, at: 0)
        if cleanupHistory.count > 100 {
            cleanupHistory = Array(cleanupHistory.prefix(100))
        }
        if let data = try? JSONEncoder().encode(cleanupHistory) {
            UserDefaults.standard.set(data, forKey: Self.historyDefaultsKey)
        }
    }

    private func loadCleanupHistory() {
        guard let data = UserDefaults.standard.data(forKey: Self.historyDefaultsKey),
              let decoded = try? JSONDecoder().decode([CleanupHistoryRecord].self, from: data) else {
            return
        }
        cleanupHistory = decoded
    }

    // MARK: - Computed Totals

    public var totalJunkBytes: Int64 {
        junkItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var selectedJunkBytes: Int64 {
        junkItems.filter { $0.isSelected && $0.canClean }.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalLeftoversBytes: Int64 {
        leftoverGroups.reduce(0) { $0 + $1.totalSizeBytes }
    }

    public var selectedLeftoversBytes: Int64 {
        leftoverGroups.filter(\.isSelected).reduce(0) { $0 + $1.totalSizeBytes }
    }

    public var totalTrashBytes: Int64 {
        trashItems.reduce(0) { $0 + $1.sizeBytes }
    }

    public var selectedLargeFilesBytes: Int64 {
        largeFiles.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    // MARK: - Smart Scan (Home + Junk + Leftovers + Trash)

    public func runSmartScan() async {
        guard !isScanningJunk && !isCleaningJunk else { return }
        let start = CFAbsoluteTimeGetCurrent()
        isScanningJunk = true
        refreshFullDiskAccessStatus()
        let report = await Task.detached(priority: .utility) { IntelligentStorageScanner.scan() }.value
        applyStorageReport(report)
        isScanningJunk = false
        lastScanDurationSeconds = max(0.1, CFAbsoluteTimeGetCurrent() - start)
        // Trash and app leftovers are independent on-demand channels. Their permission
        // prompts must not prevent publishing the read-only storage diagnosis.
    }

    private func applyStorageReport(_ report: StorageReport) {
        storageReport = report
        junkItems = report.junkItems
        let history = StorageHistory.update(report)
        previousScanDate = history.0
        storageGrowth = history.1
        if let warning = history.2 { storageReport.issues.append(warning) }
    }

    // MARK: - Channel 01: System Junk (CleanerCore.JunkRule.defaults)

    public func scanSystemJunk() async {
        guard !isScanningJunk && !isCleaningJunk else { return }
        let start = CFAbsoluteTimeGetCurrent()
        isScanningJunk = true
        let result = await Task.detached(priority: .utility) { IntelligentStorageScanner.scan() }.value
        applyStorageReport(result)
        isScanningJunk = false
        lastScanDurationSeconds = max(0.1, CFAbsoluteTimeGetCurrent() - start)
    }

    public var canUndoLastCleanup: Bool {
        !lastTrashReceipts.isEmpty
    }

    public func cleanSelectedJunk() async -> Int64 {
        guard !isCleaningJunk && !isScanningJunk else { return 0 }
        isCleaningJunk = true
        defer { isCleaningJunk = false }
        let selected = junkItems.filter { $0.isSelected && $0.canClean }
        let mode = removalMode
        let outcome = await Task.detached(priority: .utility) {
            var removed = Set<UUID>()
            var receipts: [TrashReceipt] = []
            var errors: [String] = []
            var processed: Int64 = 0
            for item in selected {
                do {
                    guard let identity = item.identity else {
                        throw SafetyViolationError.unsafeRemoval("Identidade do arquivo não verificada; analise novamente.")
                    }
                    if let destination = try SafetyGuard.remove(item.url, mode: mode, expectedIdentity: identity) {
                        receipts.append(TrashReceipt(originalURL: item.url, trashURL: destination, sizeBytes: item.sizeBytes, channelTitle: "Lixo do Sistema"))
                    }
                    removed.insert(item.id)
                    processed += item.sizeBytes
                } catch { errors.append("\(item.name): \(error.localizedDescription)") }
            }
            return (removed, receipts, errors, processed)
        }.value
        junkItems.removeAll { outcome.0.contains($0.id) }
        storageReport.findings.removeAll { finding in selected.contains { outcome.0.contains($0.id) && $0.url == finding.url } }
        if mode == .trash && !outcome.1.isEmpty { lastTrashReceipts = outcome.1 }
        recordCleanupHistory(channelTitle: "Lixo do Sistema", freedBytes: outcome.3, itemsCount: outcome.0.count)
        await scanTrash()
        let action = mode == .trash ? "movidos para a Lixeira (o espaço só é liberado ao esvaziá-la)" : "removidos"
        lastStatusMessage = "\(outcome.0.count) itens \(action). Tamanho medido: \(ByteFormatter.string(from: outcome.3)); não equivale ao ganho físico em APFS."
        if !outcome.2.isEmpty {
            lastStatusMessage! += " \(outcome.2.count) itens preservados: \(outcome.2.prefix(3).joined(separator: "; "))"
        }
        return outcome.3
    }

    public func undoLastCleanup() async {
        guard !lastTrashReceipts.isEmpty else { return }
        let fm = FileManager.default
        var restoredCount = 0
        var restoredBytes: Int64 = 0
        var pending: [TrashReceipt] = []

        for receipt in lastTrashReceipts {
            if fm.fileExists(atPath: receipt.trashURL.path) {
                guard receipt.originalURL.standardizedFileURL == receipt.originalURL.resolvingSymlinksInPath(),
                      !fm.fileExists(atPath: receipt.originalURL.path) else { pending.append(receipt); continue }
                let parentDir = receipt.originalURL.deletingLastPathComponent()
                try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
                do {
                    try fm.moveItem(at: receipt.trashURL, to: receipt.originalURL)
                    restoredCount += 1
                    restoredBytes += receipt.sizeBytes
                } catch {
                    pending.append(receipt)
                }
            }
        }

        lastTrashReceipts = pending
        await scanTrash()
        lastStatusMessage = "\(restoredCount) item(ns) restaurados com sucesso para a pasta original (\(ByteFormatter.string(from: restoredBytes))). \(pending.count) restaurações pendentes, sem sobrescrever arquivos existentes."
    }

    // MARK: - Channel 02: Space Lens

    public func scanSpaceLens(at directoryURL: URL? = nil) async {
        let targetURL = directoryURL ?? FileManager.default.homeDirectoryForCurrentUser
        isScanningSpaceLens = true
        spaceLensScannedItemsCount = 0

        let (rootNode, count) = await Self.buildSpaceLensTreeOffMain(rootURL: targetURL, maxDepth: 3)
        spaceLensRoot = rootNode
        spaceLensBreadcrumbs = [rootNode]
        spaceLensScannedItemsCount = count
        isScanningSpaceLens = false
    }

    public func drillDownSpaceLens(to node: DiskNode) async {
        guard node.isDirectory else { return }
        if node.children.isEmpty {
            isScanningSpaceLens = true
            let (expanded, _) = await Self.buildSpaceLensTreeOffMain(rootURL: node.url, maxDepth: 2)
            isScanningSpaceLens = false
            spaceLensBreadcrumbs.append(expanded)
        } else {
            spaceLensBreadcrumbs.append(node)
        }
    }

    public func navigateSpaceLensBreadcrumb(to index: Int) {
        guard index >= 0 && index < spaceLensBreadcrumbs.count else { return }
        spaceLensBreadcrumbs = Array(spaceLensBreadcrumbs.prefix(index + 1))
    }

    public func moveSpaceLensNodeToTrash(_ node: DiskNode) async {
        do {
            _ = try SafetyGuard.remove(node.url, mode: removalMode)
            lastStatusMessage = "\(node.name) (\(ByteFormatter.string(from: node.sizeBytes))) movido para a Lixeira."
            if let currentRoot = spaceLensBreadcrumbs.last {
                let (refreshed, _) = await Self.buildSpaceLensTreeOffMain(rootURL: currentRoot.url, maxDepth: 2)
                spaceLensBreadcrumbs[spaceLensBreadcrumbs.count - 1] = refreshed
            }
            await scanTrash()
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    private nonisolated static func buildSpaceLensTreeOffMain(rootURL: URL, maxDepth: Int) async -> (DiskNode, Int) {
        var scannedCount = 0
        func buildNode(url: URL, currentDepth: Int) -> DiskNode {
            let fm = FileManager.default
            var isDir: ObjCBool = false
            _ = fm.fileExists(atPath: url.path, isDirectory: &isDir)
            scannedCount += 1

            if !isDir.boolValue || currentDepth >= maxDepth {
                let size = directoryOrFileSize(at: url, maxDepth: 3)
                return DiskNode(
                    url: url,
                    name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                    sizeBytes: size,
                    isDirectory: isDir.boolValue,
                    itemCount: 1,
                    children: []
                )
            }

            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                let fallbackSize = directoryOrFileSize(at: url, maxDepth: 2)
                return DiskNode(
                    url: url,
                    name: url.lastPathComponent,
                    sizeBytes: fallbackSize,
                    isDirectory: true,
                    itemCount: 1,
                    children: []
                )
            }

            var childNodes: [DiskNode] = []
            for childURL in contents {
                let childNode = buildNode(url: childURL, currentDepth: currentDepth + 1)
                if childNode.sizeBytes > 0 {
                    childNodes.append(childNode)
                }
            }
            childNodes.sort { $0.sizeBytes > $1.sizeBytes }
            let totalSize = childNodes.reduce(0) { $0 + $1.sizeBytes }
            let topChildren = Array(childNodes.prefix(14))

            return DiskNode(
                url: url,
                name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                sizeBytes: totalSize,
                isDirectory: true,
                itemCount: childNodes.count,
                children: topChildren
            )
        }

        let root = buildNode(url: rootURL, currentDepth: 0)
        return (root, scannedCount)
    }

    // MARK: - Channel 03: Large & Old Files

    public func scanLargeAndOldFiles() async {
        isScanningLargeFiles = true
        let found = await Self.scanLargeFilesOffMain()
        largeFiles = found
        isScanningLargeFiles = false
    }

    public func cleanSelectedLargeFiles() async -> Int64 {
        let selected = largeFiles.filter(\.isSelected)
        var cleaned: Int64 = 0
        var removed = Set<UUID>()
        for item in selected {
            do {
                _ = try SafetyGuard.remove(item.url, mode: removalMode)
                cleaned += item.sizeBytes
                removed.insert(item.id)
            } catch {
                lastStatusMessage = error.localizedDescription
            }
        }
        largeFiles.removeAll { removed.contains($0.id) }
        if cleaned > 0 {
            recordCleanupHistory(channelTitle: "Grandes e Antigos", freedBytes: cleaned, itemsCount: removed.count)
            await scanTrash()
            lastStatusMessage = "Movidos \(ByteFormatter.string(from: cleaned)) de arquivos grandes para a Lixeira."
        }
        return cleaned
    }

    private nonisolated static func scanLargeFilesOffMain() async -> [LargeFileItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let scanRoots = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Public"),
            home.appendingPathComponent("Developer")
        ]
        let minimumSize: Int64 = 15 * 1024 * 1024 // 15 MB
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isDirectoryKey,
            .isPackageKey,
            .isUbiquitousItemKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .contentAccessDateKey,
            .contentModificationDateKey
        ]

        var items: [LargeFileItem] = []

        for root in scanRoots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.path.contains(".photoslibrary") {
                    enumerator.skipDescendants()
                    continue
                }
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else {
                    continue
                }
                let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
                guard size >= minimumSize else { continue }
                let accessDate = values.contentAccessDate ?? values.contentModificationDate ?? Date()
                let category = LargeFileCategory.categorize(url: fileURL)
                let isICloud = (values.isUbiquitousItem == true) || fileURL.path.contains("Mobile Documents")
                items.append(
                    LargeFileItem(
                        url: fileURL,
                        name: fileURL.lastPathComponent,
                        sizeBytes: size,
                        lastAccessed: accessDate,
                        category: category,
                        isInICloud: isICloud
                    )
                )
            }
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Channel 04 & 05: Uninstaller & Leftovers (CleanerCore.LeftoverFinder)

    public func scanAppsAndLeftovers() async {
        isScanningApps = true
        isScanningLeftovers = true
        let (apps, leftovers) = await Self.scanAppsAndLeftoversOffMain()
        installedApps = apps
        leftoverGroups = leftovers
        isScanningApps = false
        isScanningLeftovers = false
    }

    public func uninstallApp(_ app: InstalledApp) async -> Bool {
        var totalRemoved: Int64 = 0
        do {
            for related in app.relatedFiles where related.isSelected {
                _ = try SafetyGuard.remove(related.url, mode: removalMode)
                totalRemoved += related.sizeBytes
            }
            _ = try SafetyGuard.remove(app.bundleURL, mode: removalMode)
            totalRemoved += app.appSizeBytes
            installedApps.removeAll { $0.id == app.id }
            recordCleanupHistory(channelTitle: "Desinstalador (\(app.name))", freedBytes: totalRemoved, itemsCount: 1 + app.relatedFiles.count)
            await scanTrash()
            lastStatusMessage = "\(app.name) e seus restos (\(ByteFormatter.string(from: totalRemoved))) foram movidos para a Lixeira."
            return true
        } catch {
            lastStatusMessage = "Não foi possível remover \(app.name): \(error.localizedDescription)"
            return false
        }
    }

    public func cleanSelectedLeftovers() async -> Int64 {
        let selectedGroups = leftoverGroups.filter(\.isSelected)
        var cleaned: Int64 = 0
        var removedGroupIDs = Set<UUID>()

        for group in selectedGroups {
            var allMoved = true
            for file in group.files {
                do {
                    _ = try SafetyGuard.remove(file.url, mode: removalMode)
                    cleaned += file.sizeBytes
                } catch {
                    allMoved = false
                }
            }
            if allMoved {
                removedGroupIDs.insert(group.id)
            }
        }

        leftoverGroups.removeAll { removedGroupIDs.contains($0.id) }
        if cleaned > 0 {
            recordCleanupHistory(channelTitle: "Restos de Apps", freedBytes: cleaned, itemsCount: removedGroupIDs.count)
            await scanTrash()
            lastStatusMessage = "Restos de apps (\(ByteFormatter.string(from: cleaned))) movidos para a Lixeira."
        }
        return cleaned
    }

    private nonisolated static func scanAppsAndLeftoversOffMain() async -> ([InstalledApp], [OrphanedLeftoverGroup]) {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            home.appendingPathComponent("Applications")
        ]

        // Exact user Library locations from CleanerCore.LeftoverFinder
        let libraryLocations: [(String, String, LeftoverKind, LeftoverCaution?)] = [
            ("Library/Application Support", "Application Support", .data, nil),
            ("Library/Containers", "Containers", .data, nil),
            ("Library/Group Containers", "Group Containers", .data, .shared),
            ("Library/Caches", "Caches", .caches, nil),
            ("Library/Cookies", "Cookies", .cookies, nil),
            ("Library/HTTPStorages", "HTTPStorages", .cookies, nil),
            ("Library/Logs", "Logs", .logs, nil),
            ("Library/Preferences", "Preferences", .preferences, nil),
            ("Library/Saved Application State", "Saved State", .savedState, nil),
            ("Library/WebKit", "WebKit", .data, nil),
            ("Library/LaunchAgents", "LaunchAgents", .startup, nil)
        ]

        struct LibraryEntry {
            let url: URL
            let nameLower: String
            let locationType: String
            let kind: LeftoverKind
            let caution: LeftoverCaution?
        }

        var libraryEntries: [LibraryEntry] = []
        for (relPath, locType, kind, caution) in libraryLocations {
            let dirURL = home.appendingPathComponent(relPath)
            guard let items = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            for item in items {
                libraryEntries.append(
                    LibraryEntry(
                        url: item,
                        nameLower: item.lastPathComponent.lowercased(),
                        locationType: locType,
                        kind: kind,
                        caution: caution
                    )
                )
            }
        }

        var apps: [InstalledApp] = []
        var knownBundleIDs = Set<String>()
        var knownAppNames = Set<String>()
        var claimedLibraryURLs = Set<URL>()

        for appDir in appDirs where fm.fileExists(atPath: appDir.path) {
            guard let contents = try? fm.contentsOfDirectory(at: appDir, includingPropertiesForKeys: [.contentAccessDateKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for bundleURL in contents where bundleURL.pathExtension.lowercased() == "app" {
                let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
                let plist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
                let bundleID = (plist?["CFBundleIdentifier"] as? String) ?? ""
                let displayName = (plist?["CFBundleDisplayName"] as? String)
                    ?? (plist?["CFBundleName"] as? String)
                    ?? bundleURL.deletingPathExtension().lastPathComponent
                let shortVersion = (plist?["CFBundleShortVersionString"] as? String)
                    ?? (plist?["CFBundleVersion"] as? String)
                    ?? "1.0"
                let buildVersion = plist?["CFBundleVersion"] as? String
                let feedURLStr = plist?["SUFeedURL"] as? String
                let feedURL = feedURLStr.flatMap { URL(string: $0) }
                let receiptURL = bundleURL.appendingPathComponent("Contents/_MASReceipt/receipt")
                let hasAppStoreReceipt = fm.fileExists(atPath: receiptURL.path)
                let lastUsed = (try? bundleURL.resourceValues(forKeys: [.contentAccessDateKey]))?.contentAccessDate

                if !bundleID.isEmpty {
                    knownBundleIDs.insert(bundleID.lowercased())
                }
                knownAppNames.insert(displayName.lowercased())
                knownAppNames.insert(bundleURL.deletingPathExtension().lastPathComponent.lowercased())

                if bundleID.lowercased().hasPrefix("com.apple.") {
                    continue
                }

                let appSize = directoryOrFileSize(at: bundleURL, maxDepth: 4)
                let bundleIDLower = bundleID.lowercased()
                let nameLower = displayName.lowercased()

                var related: [AppRelatedFile] = []
                for entry in libraryEntries {
                    let matchesID = !bundleIDLower.isEmpty && entry.nameLower.contains(bundleIDLower)
                    let matchesName = nameLower.count >= 4 && entry.nameLower == nameLower
                    if matchesID || matchesName {
                        claimedLibraryURLs.insert(entry.url)
                        let fSize = directoryOrFileSize(at: entry.url, maxDepth: 3)
                        if fSize > 0 {
                            related.append(
                                AppRelatedFile(
                                    url: entry.url,
                                    locationType: entry.locationType,
                                    kind: entry.kind,
                                    caution: entry.caution,
                                    sizeBytes: fSize,
                                    // Group Containers shared across apps come with caution
                                    isSelected: entry.caution == nil
                                )
                            )
                        }
                    }
                }

                apps.append(
                    InstalledApp(
                        bundleURL: bundleURL,
                        name: displayName,
                        bundleIdentifier: bundleID.isEmpty ? "app.local.\(displayName)" : bundleID,
                        version: shortVersion,
                        buildVersion: buildVersion,
                        feedURL: feedURL,
                        hasAppStoreReceipt: hasAppStoreReceipt,
                        appSizeBytes: appSize,
                        lastUsedDate: lastUsed,
                        relatedFiles: related.sorted { $0.sizeBytes > $1.sizeBytes }
                    )
                )
            }
        }

        apps.sort { $0.totalSizeBytes > $1.totalSizeBytes }

        // Detect orphaned leftovers in ~/Library
        var orphanMap: [String: [AppRelatedFile]] = [:]
        for entry in libraryEntries where !claimedLibraryURLs.contains(entry.url) {
            guard entry.locationType == "Application Support" ||
                  entry.locationType == "Caches" ||
                  entry.locationType == "Saved State" ||
                  entry.locationType == "Containers" else {
                continue
            }
            let rawName = entry.url.lastPathComponent
            let lower = rawName.lowercased()

            if lower.hasPrefix("com.apple.") ||
               lower.hasPrefix("apple") ||
               SafetyGuard.protectedCacheIdentifiers.contains(lower) ||
               lower.contains("cloudkit") ||
               lower.contains("crashreporter") ||
               lower.contains("knowledge") ||
               lower == "caches" ||
               lower.contains("meucleaner") {
                continue
            }

            let matchesInstalled = knownBundleIDs.contains(where: { lower.contains($0) }) ||
                knownAppNames.contains(where: { $0.count >= 4 && lower.contains($0) })

            if !matchesInstalled {
                let size = directoryOrFileSize(at: entry.url, maxDepth: 3)
                guard size > 256 * 1024 else { continue }
                let fileItem = AppRelatedFile(
                    url: entry.url,
                    locationType: entry.locationType,
                    kind: entry.kind,
                    caution: entry.caution,
                    sizeBytes: size,
                    isSelected: false
                )
                orphanMap[rawName, default: []].append(fileItem)
            }
        }

        let leftovers: [OrphanedLeftoverGroup] = orphanMap.map { key, files in
            let readableName = Self.prettifyIdentifier(key)
            return OrphanedLeftoverGroup(
                inferredAppName: readableName,
                identifierHint: key,
                files: files,
                isSelected: false
            )
        }.sorted { $0.totalSizeBytes > $1.totalSizeBytes }

        return (apps, leftovers)
    }

    private nonisolated static func prettifyIdentifier(_ raw: String) -> String {
        if raw.contains(".") {
            let parts = raw.split(separator: ".").map(String.init)
            if let last = parts.last, last.lowercased() != "savedstate" && last.lowercased() != "plist" {
                return last.prefix(1).uppercased() + last.dropFirst()
            } else if parts.count >= 2 {
                let candidate = parts[parts.count - 2]
                return candidate.prefix(1).uppercased() + candidate.dropFirst()
            }
        }
        return raw
    }

    // MARK: - Channel 06: Trash

    public func scanTrash() async {
        isScanningTrash = true
        let result = await Self.scanTrashOffMain()
        trashItems = result.items
        hasScannedTrash = result.issue == nil
        isScanningTrash = false
        if let issue = result.issue {
            lastStatusMessage = issue
            return
        }
        await checkTrashedAppsForLeftovers()
    }

    public func emptyTrashPermanently() async {
        let items = trashItems
        let outcome = await Task.detached(priority: .utility) {
            var removed = 0
            var blocked = 0
            for item in items {
                do { _ = try SafetyGuard.remove(item.url, mode: .permanent); removed += 1 }
                catch { blocked += 1 }
            }
            return (removed, blocked)
        }.value
        await scanTrash()
        lastStatusMessage = "\(outcome.0) itens removidos; \(outcome.1) preservados por uso, conteúdo protegido ou erro de leitura."
    }

    private nonisolated static func scanTrashOffMain() async -> (items: [TrashItem], issue: String?) {
        let fm = FileManager.default
        let trashURL = fm.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let listing = StorageDirectory.list(trashURL)
        if let issue = listing.issue { return ([], issue) }
        let contents = listing.urls

        var results: [TrashItem] = []
        for url in contents {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .addedToDirectoryDateKey, .contentModificationDateKey])
            let size = directoryOrFileSize(at: url, maxDepth: 4)
            results.append(
                TrashItem(
                    url: url,
                    name: url.lastPathComponent,
                    sizeBytes: size,
                    deletedDate: values?.addedToDirectoryDate ?? values?.contentModificationDate,
                    isDirectory: values?.isDirectory ?? false
                )
            )
        }
        return (results.sorted { $0.sizeBytes > $1.sizeBytes }, nil)
    }

    // MARK: - Channel 07: App Updater (Homebrew + Sparkle Appcast XML + App Store iTunes Lookup)

    public func scanForAppUpdates() async {
        isScanningUpdates = true
        if installedApps.isEmpty {
            let (apps, leftovers) = await Self.scanAppsAndLeftoversOffMain()
            installedApps = apps
            leftoverGroups = leftovers
        }
        let updates = await Self.checkAppUpdatesOffMain(installedApps: installedApps)
        updatableApps = updates
        isScanningUpdates = false
    }

    public func toggleSkipUpdate(for appID: UUID) {
        if let idx = updatableApps.firstIndex(where: { $0.id == appID }) {
            updatableApps[idx].isSkipped.toggle()
        }
    }

    private nonisolated static func checkAppUpdatesOffMain(installedApps: [InstalledApp]) async -> [UpdatableApp] {
        var found: [UpdatableApp] = []

        // 1. Homebrew Cask Updates (`brew outdated --cask --json=v2`)
        let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        if let brewPath = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["outdated", "--cask", "--json=v2"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            if (try? process.run()) != nil {
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let casks = json["casks"] as? [[String: Any]] {
                    for cask in casks {
                        let token = (cask["name"] as? String) ?? "cask"
                        let currentArr = cask["installed_versions"] as? [String]
                        let currentVer = currentArr?.first ?? "?"
                        let latestVer = (cask["current_version"] as? String) ?? "Nova"
                        found.append(
                            UpdatableApp(
                                name: token.capitalized,
                                bundleIdentifier: "homebrew.cask.\(token)",
                                bundleURL: nil,
                                currentVersion: currentVer,
                                latestVersion: latestVer,
                                source: .homebrew,
                                releaseNotes: "Atualização via Homebrew (`brew upgrade --cask \(token)`).",
                                caskToken: token
                            )
                        )
                    }
                }
            }
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = 4.0
        sessionConfig.timeoutIntervalForResource = 5.0
        let session = URLSession(configuration: sessionConfig)

        // 2. App Store Lookup API (`https://itunes.apple.com/lookup?bundleId=...`) for MAS apps
        let masApps = installedApps.filter(\.hasAppStoreReceipt).prefix(12)
        for app in masApps {
            guard let encodedID = app.bundleIdentifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let lookupURL = URL(string: "https://itunes.apple.com/lookup?bundleId=\(encodedID)&country=BR") else {
                continue
            }
            if let (data, _) = try? await session.data(from: lookupURL),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let results = json["results"] as? [[String: Any]],
               let first = results.first,
               let storeVersion = first["version"] as? String,
               AppVersion.isNewer(storeVersion, than: app.version) {
                let notes = (first["releaseNotes"] as? String) ?? "Disponível na Mac App Store."
                let trackViewUrl = (first["trackViewUrl"] as? String).flatMap { URL(string: $0) }
                found.append(
                    UpdatableApp(
                        name: app.name,
                        bundleIdentifier: app.bundleIdentifier,
                        bundleURL: app.bundleURL,
                        currentVersion: app.version,
                        latestVersion: storeVersion,
                        source: .appStore,
                        releaseNotes: notes,
                        downloadOrStoreURL: trackViewUrl
                    )
                )
            }
        }

        // 3. Sparkle Appcast XML Feeds (`SUFeedURL`)
        let sparkleApps = installedApps.filter { $0.feedURL != nil }.prefix(15)
        for app in sparkleApps {
            guard let feedURL = app.feedURL else { continue }
            if let (data, _) = try? await session.data(from: feedURL),
               let parsed = SimpleAppcastParser.parseLatestVersion(from: data) {
                if AppVersion.isNewer(parsed.version, than: app.version) {
                    found.append(
                        UpdatableApp(
                            name: app.name,
                            bundleIdentifier: app.bundleIdentifier,
                            bundleURL: app.bundleURL,
                            currentVersion: app.version,
                            latestVersion: parsed.version,
                            source: .sparkle,
                            releaseNotes: parsed.notes.isEmpty ? "Nova versão publicada no feed Sparkle (\(feedURL.host ?? ""))." : parsed.notes,
                            downloadOrStoreURL: parsed.downloadURL
                        )
                    )
                }
            }
        }

        return found
    }

    // MARK: - Fast File/Directory Size Calculation

    public nonisolated static func directoryOrFileSize(at url: URL, maxDepth: Int) -> Int64 {
        // maxDepth kept for source compatibility. Size must include hidden and deep files.
        StorageMeter.measure(url).allocatedBytes
    }

}

// MARK: - Lightweight Sparkle Appcast XML Parser (CleanerCore.AppcastParserDelegate)

private final class SimpleAppcastParser: NSObject, XMLParserDelegate {
    struct ParsedUpdate {
        let version: String
        let notes: String
        let downloadURL: URL?
    }

    private var latestShortVersion: String?
    private var latestBuildVersion: String?
    private var latestDownloadURL: URL?
    private var currentElement: String = ""
    private var descriptionBuffer: String = ""
    private var insideItem: Bool = false
    private var capturedFirstItem: Bool = false

    static func parseLatestVersion(from data: Data) -> ParsedUpdate? {
        let delegate = SimpleAppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        _ = parser.parse()
        guard let ver = delegate.latestShortVersion ?? delegate.latestBuildVersion, !ver.isEmpty else {
            return nil
        }
        let strippedNotes = delegate.descriptionBuffer
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedUpdate(
            version: ver,
            notes: String(strippedNotes.prefix(260)),
            downloadURL: delegate.latestDownloadURL
        )
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard !capturedFirstItem else { return }
        currentElement = elementName.lowercased()
        if currentElement == "item" {
            insideItem = true
        } else if insideItem && currentElement == "enclosure" {
            if let shortVer = attributeDict["sparkle:shortVersionString"] {
                latestShortVersion = shortVer
            }
            if let buildVer = attributeDict["sparkle:version"] {
                latestBuildVersion = buildVer
            }
            if let urlStr = attributeDict["url"] {
                latestDownloadURL = URL(string: urlStr)
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard insideItem && !capturedFirstItem else { return }
        if currentElement == "sparkle:shortversionstring" && latestShortVersion == nil {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { latestShortVersion = trimmed }
        } else if currentElement == "sparkle:version" && latestBuildVersion == nil {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { latestBuildVersion = trimmed }
        } else if currentElement == "description" {
            descriptionBuffer += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName.lowercased() == "item" && insideItem {
            insideItem = false
            capturedFirstItem = true
        }
    }
}
