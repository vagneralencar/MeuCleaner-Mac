import Foundation

extension DiskScannerService {
    // Additional tools use the same review, destination, revalidation and history.
    // Preparing a review never removes files.
    func prepareFileReview(_ urls: [URL], title: String, consequence: String) async {
        guard !isScanningJunk && !isCleaningJunk && !isRestoring else { return }
        isScanningJunk = true
        lastStatusMessage = "Verificando os itens selecionados para revisão. Nenhum arquivo foi apagado."
        let findings = await Task.detached(priority: .utility) {
            var scan = IntelligentStorageScanner(usage: .capture())
            var roots: [URL] = []
            for url in urls.sorted(by: { $0.path.count < $1.path.count }) {
                if !roots.contains(where: { StoragePaths.contains($0.path, url.path) }) { roots.append(url) }
            }
            for url in roots {
                var protection: String?
                do { try SafetyGuard.validateCanMoveToTrash(url) }
                catch { protection = error.localizedDescription }
                scan.append(url, title: url.lastPathComponent, category: nil, review: true, preserve: protection)
            }
            return scan.report.findings.map { finding in
                var item = finding
                item.explicitRemovalConsequence = consequence
                return item
            }
        }.value
        isScanningJunk = false
        cleanupRequest = CleanupRequest(title: title, target: .files(findings),
                                        initialSelection: Set(findings.filter(\.canReviewRemoval).map(\.id)))
        lastStatusMessage = nil
    }
    func review(_ findings: [StorageFinding], title: String, selection: Set<String> = []) {
        guard !isScanningJunk && !isCleaningJunk else { return }
        cleanupRequest = CleanupRequest(title: title, target: .files(findings), initialSelection: selection)
    }

    func performReviewedCleanup(_ request: CleanupRequest, selection: Set<String>, mode: RemovalMode) async -> CleanupOutcome {
        guard !isCleaningJunk && !isScanningJunk && !isRestoring else {
            return CleanupOutcome(rows: [.init(id: "busy", title: "Operação em andamento", success: false, message: "Aguarde a análise ou limpeza atual.")])
        }
        isCleaningJunk = true
        defer { isCleaningJunk = false; cleanupProgress = "" }
        var outcome = CleanupOutcome(freeBefore: IntelligentStorageScanner.freeSpace(at: SafetyGuard.homeDirectoryURL))
        var receipts: [TrashReceipt] = []
        switch request.target {
        case .files(let files):
            let chosen = files.filter { selection.contains($0.id) }
            for (index, file) in chosen.enumerated() {
                cleanupProgress = "Verificando e processando \(index + 1) de \(chosen.count): \(file.title)"
                let result: (CleanupResultRow, TrashReceipt?) = await Task.detached(priority: .utility) {
                    do {
                        guard file.canReviewRemoval, let identity = file.identity else {
                            throw SafetyViolationError.unsafeRemoval("Item protegido, em uso ou sem identidade verificada.")
                        }
                        let destination = try SafetyGuard.remove(file.url, mode: mode, expectedIdentity: identity)
                        let receipt = destination.map { TrashReceipt(originalURL: file.url, trashURL: $0, sizeBytes: file.measurement.allocatedBytes, channelTitle: request.title) }
                        let message = mode == .trash ? "Movido para a Lixeira; pode ser restaurado." : "Apagado permanentemente após nova verificação."
                        return (CleanupResultRow(id: file.id, title: file.title, success: true, message: message), receipt)
                    } catch {
                        return (CleanupResultRow(id: file.id, title: file.title, success: false, message: error.localizedDescription), nil)
                    }
                }.value
                outcome.rows.append(result.0)
                if let receipt = result.1 { receipts.append(receipt) }
            }
        case .images(let inventory):
            let chosen = inventory.images.filter { selection.contains($0.id) }
            for (index, image) in chosen.enumerated() {
                cleanupProgress = "Verificando containers e imagem \(index + 1) de \(chosen.count)"
                let row = await Task.detached(priority: .utility) {
                    do {
                        let message = try DockerMaintenance(socket: inventory.socket).removeImage(image, expected: inventory)
                        return CleanupResultRow(id: image.id, title: image.title, success: true, message: message)
                    } catch { return CleanupResultRow(id: image.id, title: image.title, success: false, message: error.localizedDescription) }
                }.value
                outcome.rows.append(row)
            }
        case .buildCache(let inventory):
            guard selection.contains("build-cache") else { return outcome }
            cleanupProgress = "Conferindo novamente o uso do cache no Docker local..."
            outcome.rows = await Task.detached(priority: .utility) {
                do {
                    let message = try DockerMaintenance(socket: inventory.socket).pruneCache(expected: inventory)
                    return [CleanupResultRow(id: "build-cache", title: "Cache de builds", success: true, message: message)]
                } catch { return [CleanupResultRow(id: "build-cache", title: "Cache de builds", success: false, message: error.localizedDescription)] }
            }.value
        }
        let succeeded = Set(outcome.rows.filter(\.success).map(\.id))
        junkItems.removeAll { succeeded.contains($0.url.path) }
        storageReport.findings.removeAll { succeeded.contains($0.id) }
        largeFiles.removeAll { succeeded.contains($0.url.path) }
        devArtifacts.removeAll { succeeded.contains($0.url.path) }
        installedApps.removeAll { succeeded.contains($0.bundleURL.path) }
        for index in installedApps.indices { installedApps[index].relatedFiles.removeAll { succeeded.contains($0.url.path) } }
        for index in leftoverGroups.indices { leftoverGroups[index].files.removeAll { succeeded.contains($0.url.path) } }
        leftoverGroups.removeAll { $0.files.isEmpty }
        for index in duplicateGroups.indices { duplicateGroups[index].files.removeAll { succeeded.contains($0.url.path) } }
        duplicateGroups.removeAll { $0.files.count < 2 }
        trashedAppAlerts.removeAll { $0.leftoverFiles.allSatisfy { succeeded.contains($0.url.path) } }
        if !receipts.isEmpty { lastTrashReceipts = receipts }
        outcome.freeAfter = IntelligentStorageScanner.freeSpace(at: SafetyGuard.homeDirectoryURL)
        if case .files = request.target, mode == .trash {
            outcome.note = "Os itens continuam ocupando espaço na Lixeira até ela ser esvaziada. Você pode usar Desfazer para restaurá-los."
        }
        let destination: String
        if case .files = request.target {
            destination = mode == .trash ? "Destino: Lixeira" : "Exclusão permanente"
        } else { destination = "Remoção permanente pelo Docker" }
        let activity = CleanupActivity(title: request.title, destination: destination, rows: outcome.rows,
                                       freeBefore: outcome.freeBefore, freeAfter: outcome.freeAfter, note: outcome.note)
        cleanupActivities.insert(activity, at: 0)
        if cleanupActivities.count > 100 { cleanupActivities = Array(cleanupActivities.prefix(100)) }
        if !receipts.isEmpty { restorableActivityID = activity.id }
        lastStatusMessage = "\(outcome.rows.filter(\.success).count) operações confirmadas; \(outcome.rows.filter { !$0.success }.count) itens preservados ou não confirmados."
        return outcome
    }
}
