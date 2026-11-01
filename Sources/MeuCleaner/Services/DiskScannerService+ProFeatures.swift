import Foundation
import AppKit
import CryptoKit

extension DiskScannerService {
    // MARK: - Computed Totals for Pro Channels

    public var totalDevArtifactsBytes: Int64 {
        devArtifacts.reduce(0) { $0 + $1.sizeBytes }
    }

    public var selectedDevArtifactsBytes: Int64 {
        devArtifacts.filter(\.isSelected).reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalDuplicatesReclaimableBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.maxReclaimableBytes }
    }

    public var selectedDuplicatesReclaimableBytes: Int64 {
        duplicateGroups.reduce(0) { $0 + $1.selectedReclaimableBytes }
    }

    // MARK: - Channel 08: Dev & IA Cleaner

    public func scanDevAndAIArtifacts() async {
        isScanningDevArtifacts = true
        let found = await Self.scanDevAndAIOffMain()
        devArtifacts = found
        isScanningDevArtifacts = false
    }

    public func cleanSelectedDevArtifacts() async -> Int64 {
        await prepareFileReview(devArtifacts.filter(\.isSelected).map(\.url), title: "Arquivos de desenvolvimento",
                                consequence: "Pode exigir novos downloads ou recompilação. Projetos e worktrees permanecem protegidos.")
        return 0
    }

    public func inspectXcodeSimulators() async {
        await scanSystemJunk()
        lastStatusMessage = "Simuladores e seus dados foram preservados. Consulte o diagnóstico na Varredura Inteligente; indisponível não significa descartável."
    }

    private nonisolated static func scanDevAndAIOffMain() async -> [DevArtifactItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var items: [DevArtifactItem] = []

        // 1. Local AI Models (Ollama, Hugging Face Hub, LM Studio)
        let aiTargets: [(String, String, String)] = [
            (".ollama/models", "Ollama Local LLMs", "models"),
            (".cache/huggingface/hub", "Hugging Face Hub Models", "hub"),
            (".cache/lm-studio/models", "LM Studio GGUF Models", "models")
        ]
        for (relPath, projectTitle, folderName) in aiTargets {
            let url = home.appendingPathComponent(relPath)
            if fm.fileExists(atPath: url.path) {
                let size = directoryOrFileSize(at: url, maxDepth: 5)
                if size > 512 * 1024 {
                    let modDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
                    items.append(
                        DevArtifactItem(
                            url: url,
                            projectName: projectTitle,
                            artifactFolderName: folderName,
                            category: .aiModels,
                            sizeBytes: size,
                            lastModified: modDate,
                            isSelected: false
                        )
                    )
                }
            }
        }

        // 2. Project Directories (~/dev, ~/Developer, ~/Projects, ~/Code, ~/Workspace)
        let workspaceRoots = [
            home.appendingPathComponent("dev"),
            home.appendingPathComponent("Developer"),
            home.appendingPathComponent("Projects"),
            home.appendingPathComponent("Code"),
            home.appendingPathComponent("Workspace")
        ]

        let artifactFolderRules: [String: DevArtifactCategory] = [
            "node_modules": .nodeModules,
            ".next": .nodeModules,
            ".venv": .pythonVenv,
            "venv": .pythonVenv,
            "target": .rustSwiftBuild,
            ".build": .rustSwiftBuild
        ]

        for root in workspaceRoots where fm.fileExists(atPath: root.path) {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            while let currentURL = enumerator.nextObject() as? URL {
                if enumerator.level > 4 {
                    enumerator.skipDescendants()
                    continue
                }
                let folderName = currentURL.lastPathComponent
                if folderName == ".git" {
                    enumerator.skipDescendants()
                    continue
                }

                guard let category = artifactFolderRules[folderName] else { continue }
                let parentURL = currentURL.deletingLastPathComponent()

                // Avoid deleting active MeuCleaner build folder while running
                if parentURL.lastPathComponent.lowercased() == "meucleaner" {
                    enumerator.skipDescendants()
                    continue
                }

                // For "target", ensure Cargo.toml or pom.xml exists in parent so we don't flag source folders named target
                if folderName == "target" {
                    let hasCargo = fm.fileExists(atPath: parentURL.appendingPathComponent("Cargo.toml").path)
                    let hasPom = fm.fileExists(atPath: parentURL.appendingPathComponent("pom.xml").path)
                    if !hasCargo && !hasPom { continue }
                }

                enumerator.skipDescendants()

                let size = directoryOrFileSize(at: currentURL, maxDepth: 5)
                guard size >= 2 * 1024 * 1024 else { continue } // At least 2 MB

                let modDate = (try? parentURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? (try? currentURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    ?? Date()

                items.append(
                    DevArtifactItem(
                        url: currentURL,
                        projectName: parentURL.lastPathComponent,
                        artifactFolderName: folderName,
                        category: category,
                        sizeBytes: size,
                        lastModified: modDate
                    )
                )
            }
        }

        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Channel 09: Startup & LaunchAgents / Daemons

    public func scanStartupAgents() async {
        isScanningStartupAgents = true
        let found = await Self.scanStartupAgentsOffMain()
        startupAgents = found
        isScanningStartupAgents = false
    }

    public func toggleLaunchAgent(_ item: StartupAgentItem) async {
        let shouldUnload = item.isLoadedInLaunchd
        let plistPath = item.plistURL.path
        await Task.detached {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
            proc.arguments = [shouldUnload ? "unload" : "load", plistPath]
            try? proc.run()
            proc.waitUntilExit()
        }.value

        if let idx = startupAgents.firstIndex(where: { $0.id == item.id }) {
            startupAgents[idx].isLoadedInLaunchd.toggle()
            let stateText = startupAgents[idx].isLoadedInLaunchd ? "ativado" : "pausado"
            lastStatusMessage = "Agente \(item.label) \(stateText) via launchctl."
        }
    }

    public func removeStartupAgentToTrash(_ item: StartupAgentItem) async {
        guard item.scope == .userAgent else {
            lastStatusMessage = "Agentes globais/sistema em /Library devem ser revisados manualmente no Finder."
            return
        }
        if item.isLoadedInLaunchd {
            await toggleLaunchAgent(item)
        }
        do {
            _ = try SafetyGuard.remove(item.plistURL, mode: .trash)
            startupAgents.removeAll { $0.id == item.id }
            lastStatusMessage = "Agente de inicialização \(item.label) movido para a Lixeira."
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    private nonisolated static func scanStartupAgentsOffMain() async -> [StartupAgentItem] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // Query currently loaded labels from `launchctl list`
        var loadedLabels = Set<String>()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        proc.arguments = ["list"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        if (try? proc.run()) != nil {
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let text = String(data: data, encoding: .utf8) {
                for line in text.split(separator: "\n") {
                    let cols = line.split(whereSeparator: { $0 == "\t" || $0 == " " })
                    if let lastCol = cols.last {
                        loadedLabels.insert(String(lastCol))
                    }
                }
            }
        }

        let directories: [(URL, StartupAgentScope)] = [
            (home.appendingPathComponent("Library/LaunchAgents"), .userAgent),
            (URL(fileURLWithPath: "/Library/LaunchAgents"), .globalAgent),
            (URL(fileURLWithPath: "/Library/LaunchDaemons"), .systemDaemon)
        ]

        var results: [StartupAgentItem] = []

        for (dirURL, scope) in directories where fm.fileExists(atPath: dirURL.path) {
            guard let files = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else {
                continue
            }
            for fileURL in files where fileURL.pathExtension.lowercased() == "plist" {
                let dict = NSDictionary(contentsOf: fileURL) as? [String: Any]
                let label = (dict?["Label"] as? String) ?? fileURL.deletingPathExtension().lastPathComponent
                if label.lowercased().hasPrefix("com.apple.") {
                    continue
                }
                let program: String
                if let prog = dict?["Program"] as? String {
                    program = prog
                } else if let args = dict?["ProgramArguments"] as? [String], let first = args.first {
                    program = first
                } else {
                    program = fileURL.path
                }
                let runAtLoad = (dict?["RunAtLoad"] as? Bool) ?? false
                let keepAlive = (dict?["KeepAlive"] as? Bool) ?? (dict?["KeepAlive"] != nil)
                let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 512)
                let isLoaded = loadedLabels.contains(label)

                results.append(
                    StartupAgentItem(
                        plistURL: fileURL,
                        label: label,
                        programPath: program,
                        scope: scope,
                        runAtLoad: runAtLoad,
                        keepAlive: keepAlive,
                        sizeBytes: size,
                        isLoadedInLaunchd: isLoaded
                    )
                )
            }
        }

        return results.sorted { lhs, rhs in
            if lhs.isLoadedInLaunchd != rhs.isLoadedInLaunchd {
                return lhs.isLoadedInLaunchd && !rhs.isLoadedInLaunchd
            }
            return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
        }
    }

    // MARK: - Channel 10: Smart Duplicates (3-Stage SHA-256 Pipeline)

    public func scanDuplicateFiles() async {
        guard !isScanningDuplicates, !isCleaningJunk, !isRestoring else { return }
        isScanningDuplicates = true
        let result = await Task.detached(priority: .utility) {
            BoundedFilesystemRead.run(key: "duplicate-file-scan", timeout: 45) { Self.scanDuplicatesOffMain() }
        }.value
        if let result {
            duplicateGroups = result.groups
            duplicateScanIssues = result.issues
        } else {
            duplicateGroups = []
            duplicateScanIssues = ["A leitura não terminou no prazo ou ainda aguarda o macOS. Isso não significa que as pastas estejam vazias. Confira as permissões do MeuCleaner nos Ajustes do macOS e tente novamente."]
        }
        hasScannedDuplicates = true
        isScanningDuplicates = false
    }

    public func setDuplicateSelection(groupID: UUID, fileID: UUID, selected: Bool) {
        guard let groupIndex = duplicateGroups.firstIndex(where: { $0.id == groupID }),
              let fileIndex = duplicateGroups[groupIndex].files.firstIndex(where: { $0.id == fileID }) else { return }
        if selected && !duplicateGroups[groupIndex].files[fileIndex].isSelectedForRemoval &&
            duplicateGroups[groupIndex].files.filter({ !$0.isSelectedForRemoval }).count <= 1 {
            lastStatusMessage = "Mantenha pelo menos uma cópia de cada grupo."
            return
        }
        duplicateGroups[groupIndex].files[fileIndex].isSelectedForRemoval = selected
    }

    public func autoSelectDuplicatesKeepingNewest() {
        for groupIdx in duplicateGroups.indices {
            let sorted = duplicateGroups[groupIdx].files.sorted { $0.modifiedDate > $1.modifiedDate }
            guard let newestID = sorted.first?.id else { continue }
            for fileIdx in duplicateGroups[groupIdx].files.indices {
                let fileID = duplicateGroups[groupIdx].files[fileIdx].id
                duplicateGroups[groupIdx].files[fileIdx].isSelectedForRemoval = (fileID != newestID)
            }
        }
    }

    public func cleanSelectedDuplicates() async -> Int64 {
        guard !duplicateGroups.contains(where: { !$0.files.isEmpty && $0.files.allSatisfy(\.isSelectedForRemoval) }) else {
            lastStatusMessage = "Mantenha pelo menos uma cópia de cada grupo antes de revisar."
            return 0
        }
        await prepareFileReview(duplicateGroups.flatMap { $0.files.filter(\.isSelectedForRemoval).map(\.url) }, title: "Cópias selecionadas",
                                consequence: "Uma cópia escolhida será removida. Confirme quais arquivos deseja manter; igualdade não determina importância.")
        return 0
    }

    private nonisolated static func scanDuplicatesOffMain() -> (groups: [DuplicateGroup], issues: [String]) {
        let fm = FileManager.default
        var issues: [String] = []
        let deadline = Date().addingTimeInterval(45)
        let home = fm.homeDirectoryForCurrentUser
        let roots = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Music"),
            home.appendingPathComponent("Pictures"),
            home.appendingPathComponent("Public")
        ]
        let minimumDuplicateSize: Int64 = 1024 * 1024 // 1 MB minimum for fast, high-value duplicate hunting
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isPackageKey,
            .fileSizeKey,
            .contentModificationDateKey
        ]

        // Stage 1: Group files by exact byte size
        var bySize: [Int64: [(URL, Date)]] = [:]
        for root in roots {
            do { _ = try fm.attributesOfItem(atPath: root.path) }
            catch {
                let error = error as NSError
                if error.domain != NSCocoaErrorDomain || ![NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains(error.code) {
                    issues.append("Não foi possível acessar \(root.path).")
                }
                continue
            }
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { url, _ in issues.append("Não foi possível ler \(url.path)."); return true }
            ) else { issues.append("Não foi possível listar \(root.path)."); continue }

            while let url = enumerator.nextObject() as? URL {
                if Date() >= deadline {
                    issues.append("A busca alcançou o limite de tempo; parte dos arquivos não foi comparada.")
                    return ([], issues)
                }
                if url.path.contains(".photoslibrary") {
                    enumerator.skipDescendants()
                    continue
                }
                guard let vals = try? url.resourceValues(forKeys: Set(keys)) else {
                    issues.append("Não foi possível medir \(url.path)."); continue
                }
                guard vals.isRegularFile == true,
                      let fSize = vals.fileSize else { continue }
                let size64 = Int64(fSize)
                guard size64 >= minimumDuplicateSize else { continue }
                let modDate = vals.contentModificationDate ?? Date()
                bySize[size64, default: []].append((url, modDate))
            }
        }

        // Stage 2 & 3: Quick partial hash (head+tail 32 KB), then full SHA-256 on collisions
        var duplicateGroups: [DuplicateGroup] = []

        for (fileSize, candidates) in bySize where candidates.count >= 2 {
            if Date() >= deadline {
                issues.append("A comparação alcançou o limite de tempo; os resultados são parciais.")
                break
            }
            var byPartialHash: [String: [(URL, Date)]] = [:]
            for (url, modDate) in candidates {
                if let partial = partialDigest(for: url, fileSize: fileSize) {
                    byPartialHash[partial, default: []].append((url, modDate))
                } else { issues.append("Não foi possível comparar \(url.path).") }
            }

            for (_, partialMatches) in byPartialHash where partialMatches.count >= 2 {
                var byFullHash: [String: [(URL, Date)]] = [:]
                for (url, modDate) in partialMatches {
                    if let full = fullSHA256Digest(for: url) {
                        byFullHash[full, default: []].append((url, modDate))
                    } else { issues.append("Não foi possível comparar todo o conteúdo de \(url.path).") }
                }

                for (fullHash, exactMatches) in byFullHash where exactMatches.count >= 2 {
                    let sorted = exactMatches.sorted { $0.1 > $1.1 }
                    let entries = sorted.map { pair in
                        DuplicateFileEntry(
                            url: pair.0,
                            name: pair.0.lastPathComponent,
                            modifiedDate: pair.1,
                            isSelectedForRemoval: false
                        )
                    }
                    duplicateGroups.append(
                        DuplicateGroup(
                            hashHex: String(fullHash.prefix(12)),
                            eachFileSizeBytes: fileSize,
                            files: entries
                        )
                    )
                }
            }
        }

        return (duplicateGroups.sorted { $0.maxReclaimableBytes > $1.maxReclaimableBytes }, Array(Set(issues)).sorted())
    }

    private nonisolated static func partialDigest(for url: URL, fileSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let chunkSize = 32 * 1024
        var hasher = SHA256()
        if let headData = try? handle.read(upToCount: chunkSize) {
            hasher.update(data: headData)
        }
        if fileSize > Int64(chunkSize * 2) {
            try? handle.seek(toOffset: UInt64(fileSize - Int64(chunkSize)))
            if let tailData = try? handle.read(upToCount: chunkSize) {
                hasher.update(data: tailData)
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func fullSHA256Digest(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Vigia da Lixeira (Trash App Watcher) & Drag-and-Drop App Inspector

    public func inspectDroppedApp(at bundleURL: URL) async -> UUID? {
        guard bundleURL.pathExtension.lowercased() == "app" else {
            lastStatusMessage = "Arraste um pacote .app válido para inspecionar no Desinstalador."
            return nil
        }
        if let existing = installedApps.first(where: { $0.bundleURL.standardizedFileURL == bundleURL.standardizedFileURL }) {
            return existing.id
        }
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        let plist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
        let bundleID = (plist?["CFBundleIdentifier"] as? String) ?? ""
        let displayName = (plist?["CFBundleDisplayName"] as? String)
            ?? (plist?["CFBundleName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        let version = (plist?["CFBundleShortVersionString"] as? String) ?? "1.0"
        let appSize = Self.directoryOrFileSize(at: bundleURL, maxDepth: 4)
        let related = Self.findRelatedLibraryFilesForApp(bundleID: bundleID, appName: displayName)

        let customApp = InstalledApp(
            bundleURL: bundleURL,
            name: displayName,
            bundleIdentifier: bundleID.isEmpty ? "app.dropped.\(displayName)" : bundleID,
            version: version,
            appSizeBytes: appSize,
            relatedFiles: related
        )
        installedApps.insert(customApp, at: 0)
        lastStatusMessage = "\(displayName) carregado via Drag & Drop (\(related.count) restos na Library)."
        return customApp.id
    }

    public func checkTrashedAppsForLeftovers() async {
        guard trashWatcherEnabled else {
            trashedAppAlerts = []
            return
        }
        let trashApps = trashItems.filter { $0.url.pathExtension.lowercased() == "app" }
        var alerts: [TrashedAppAlert] = []

        for trashApp in trashApps {
            let infoPlistURL = trashApp.url.appendingPathComponent("Contents/Info.plist")
            let plist = NSDictionary(contentsOf: infoPlistURL) as? [String: Any]
            let bundleID = (plist?["CFBundleIdentifier"] as? String) ?? ""
            let appName = (plist?["CFBundleDisplayName"] as? String)
                ?? (plist?["CFBundleName"] as? String)
                ?? trashApp.url.deletingPathExtension().lastPathComponent
            let leftovers = Self.findRelatedLibraryFilesForApp(bundleID: bundleID, appName: appName)
            if !leftovers.isEmpty {
                alerts.append(
                    TrashedAppAlert(
                        trashedAppURL: trashApp.url,
                        appName: appName,
                        bundleIdentifier: bundleID,
                        leftoverFiles: leftovers
                    )
                )
            }
        }
        trashedAppAlerts = alerts
    }

    public func cleanTrashedAppLeftovers(_ alert: TrashedAppAlert) async {
        await prepareFileReview(alert.leftoverFiles.map(\.url), title: "Restos de \(alert.appName)",
                                consequence: "Pode remover preferências e histórico do aplicativo. Revise antes de confirmar.")
    }

    private nonisolated static func findRelatedLibraryFilesForApp(bundleID: String, appName: String) -> [AppRelatedFile] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let bundleIDLower = bundleID.lowercased()
        let nameLower = appName.lowercased()

        let locations: [(String, String, LeftoverKind)] = [
            ("Library/Application Support", "Application Support", .data),
            ("Library/Caches", "Caches", .caches),
            ("Library/Preferences", "Preferences", .preferences),
            ("Library/Containers", "Containers", .data),
            ("Library/Saved Application State", "Saved State", .savedState),
            ("Library/HTTPStorages", "HTTPStorages", .cookies)
        ]

        var found: [AppRelatedFile] = []
        for (relPath, locType, kind) in locations {
            let dirURL = home.appendingPathComponent(relPath)
            guard let items = try? fm.contentsOfDirectory(at: dirURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                continue
            }
            for item in items {
                let entryLower = item.lastPathComponent.lowercased()
                let matchesID = !bundleIDLower.isEmpty && entryLower.contains(bundleIDLower)
                let matchesName = nameLower.count >= 4 && entryLower == nameLower
                if matchesID || matchesName {
                    let size = directoryOrFileSize(at: item, maxDepth: 3)
                    if size > 0 {
                        found.append(
                            AppRelatedFile(
                                url: item,
                                locationType: locType,
                                kind: kind,
                                sizeBytes: size
                            )
                        )
                    }
                }
            }
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    // MARK: - Channel 07 Pro: 1-Click Real App Update Execution

    public func installAppUpdate(_ item: UpdatableApp) async {
        updatingAppIDs.insert(item.id)
        defer { updatingAppIDs.remove(item.id) }

        switch item.source {
        case .homebrew:
            guard let token = item.caskToken else { return }
            let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            guard let brewPath = brewPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                lastStatusMessage = "Homebrew não encontrado."
                return
            }
            lastStatusMessage = "Atualizando \(item.name) via Homebrew..."
            let success = await Task.detached { () -> Bool in
                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: brewPath)
                proc.arguments = ["upgrade", "--cask", token]
                guard (try? proc.run()) != nil else { return false }
                proc.waitUntilExit()
                return proc.terminationStatus == 0
            }.value

            if success {
                updatableApps.removeAll { $0.id == item.id }
                lastStatusMessage = "\(item.name) atualizado para \(item.latestVersion) com sucesso!"
            } else {
                lastStatusMessage = "Não foi possível atualizar \(item.name) automaticamente. Verifique no Terminal."
            }

        case .appStore:
            if let storeURL = item.downloadOrStoreURL ?? URL(string: "macappstore://showUpdatesPage") {
                NSWorkspace.shared.open(storeURL)
                lastStatusMessage = "Abrindo atualização de \(item.name) na Mac App Store..."
            }

        case .sparkle:
            if let downloadURL = item.downloadOrStoreURL {
                NSWorkspace.shared.open(downloadURL)
                lastStatusMessage = "Baixando pacote de atualização Sparkle de \(item.name)..."
            } else if let bundleURL = item.bundleURL {
                _ = try? await NSWorkspace.shared.openApplication(at: bundleURL, configuration: NSWorkspace.OpenConfiguration())
                lastStatusMessage = "\(item.name) aberto para aplicar a atualização Sparkle."
            }
        }
    }

    public func installAllAppUpdates() async {
        let activeUpdates = updatableApps.filter { !$0.isSkipped }
        for item in activeUpdates {
            await installAppUpdate(item)
        }
    }
}
