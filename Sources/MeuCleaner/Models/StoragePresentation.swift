import Foundation

enum ReviewGroup: String, CaseIterable, Identifiable {
    case recommended = "Recomendados para revisão"
    case attention = "Exigem atenção"
    case preserved = "Preservados"
    case unknown = "Não verificados"
    var id: String { rawValue }
    func contains(_ item: StorageFinding) -> Bool {
        if !item.measurement.complete { return self == .unknown }
        switch self {
        case .recommended: return item.disposition == .candidate
        case .attention: return item.disposition == .review
        case .preserved: return item.disposition == .protected || item.disposition == .inUse
        case .unknown: return item.disposition == .unverified || !item.measurement.complete
        }
    }
}

enum LocationState: String, Codable, Sendable {
    case empty = "Verificado vazio"
    case absent = "Não encontrado neste local"
    case measured = "Analisado"
    case listed = "Locais internos identificados"
    case unknown = "Não foi possível verificar"
}

struct LocationCheck: Identifiable, Sendable {
    var id: String { path }
    let path: String
    let state: LocationState
}

extension StorageFinding {
    var displayTitle: String {
        let names = ["com.openai.codex": "Cache do Codex", "Firefox": "Cache do Firefox",
                     "com.steipete.codexbar": "Cache do CodexBar", "com.raycast.macos": "Cache do Raycast",
                     "com.anthropic.claudefordesktop": "Cache do Claude",
                     "dev.vagner.MeuCleaner": "Cache do MeuCleaner", "org.swift.swiftpm": "Cache do Swift"]
        return names[title] ?? title
    }
    var statusLabel: String {
        if !measurement.complete { return "Leitura parcial" }
        switch disposition {
        case .candidate: return "Sem uso detectado"
        case .review: return "Exige sua revisão"
        case .inUse: return "Em uso · bloqueado"
        case .protected: return "Preservado"
        case .unverified: return "Uso não verificado"
        }
    }
    var consequence: String {
        if !measurement.complete || disposition == .unverified {
            return "A remoção fica bloqueada até concluir a verificação."
        }
        if disposition == .protected { return "Estes dados não serão removidos pelo MeuCleaner." }
        if disposition == .inUse { return "Feche o aplicativo responsável e analise novamente. Nada será encerrado automaticamente." }
        if let explicitRemovalConsequence { return explicitRemovalConsequence }
        switch category {
        case .userCaches, .devCaches, .dotCache, .xcode:
            return "O aplicativo pode recriar estes arquivos. O próximo uso ou build pode demorar mais."
        case .userLogs: return "Você perderá estes registros antigos de diagnóstico."
        case .browserClones: return "São cópias temporárias do aplicativo. Seu perfil, senhas e favoritos ficam preservados."
        case .installers: return "Para reinstalar, talvez seja necessário baixar o instalador novamente."
        case .incompleteDownloads: return "O download incompleto precisará ser reiniciado."
        case nil: return "Revise a finalidade destes dados antes de decidir."
        }
    }
}

extension StorageReport {
    // Parent inventories contain their children. Never present their sum as disk usage.
    var largestLocations: [StorageFinding] {
        let sorted = findings.filter { parent in
            parent.measurement.complete || !findings.contains {
                $0.id != parent.id && $0.measurement.complete && $0.measurement.allocatedBytes > 0 &&
                StoragePaths.contains(parent.url.path, $0.url.path)
            }
        }.sorted { $0.url.path.count < $1.url.path.count }
        var roots: [StorageFinding] = []
        for item in sorted where !item.sharedBlocks {
            if !roots.contains(where: { StoragePaths.contains($0.url.path, item.url.path) }) { roots.append(item) }
        }
        return roots.sorted { $0.measurement.allocatedBytes > $1.measurement.allocatedBytes }
    }
    var coverageLabel: String {
        issues.isEmpty ? "Locais conhecidos analisados" : "Cobertura parcial · \(issues.count) avisos"
    }
}

struct CleanupActivity: Identifiable, Codable, Sendable {
    var id = UUID()
    var date = Date()
    let title: String
    let destination: String
    let rows: [CleanupResultRow]
    let freeBefore: Int64
    let freeAfter: Int64
    let note: String
    var restoredAt: Date?
}
