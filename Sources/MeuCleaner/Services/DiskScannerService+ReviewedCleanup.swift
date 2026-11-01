import Foundation

extension DiskScannerService {
    func review(_ findings: [StorageFinding], title: String) {
        guard !isScanningJunk && !isCleaningJunk else { return }
        cleanupRequest = CleanupRequest(title: title, target: .files(findings))
    }

    func performReviewedCleanup(_ request: CleanupRequest, selection: Set<String>, mode: RemovalMode) async -> CleanupOutcome {
        guard !isCleaningJunk && !isScanningJunk else {
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
        if !receipts.isEmpty { lastTrashReceipts = receipts }
        outcome.freeAfter = IntelligentStorageScanner.freeSpace(at: SafetyGuard.homeDirectoryURL)
        if case .files = request.target, mode == .trash {
            outcome.note = "Os itens continuam ocupando espaço na Lixeira até ela ser esvaziada. Você pode usar Desfazer para restaurá-los."
        }
        lastStatusMessage = "\(outcome.rows.filter(\.success).count) operações confirmadas; \(outcome.rows.filter { !$0.success }.count) itens preservados ou não confirmados."
        return outcome
    }
}
