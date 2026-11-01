import Foundation

enum StorageDisposition: String, Sendable, CaseIterable {
    case candidate = "Candidato à limpeza"
    case review = "Revisar"
    case inUse = "Em uso"
    case protected = "Dados preservados"
    case unverified = "Não verificado"
    var allowsSelection: Bool { self == .candidate || self == .review }
}

struct StorageFinding: Identifiable, Sendable {
    var id: String { url.path }
    let url: URL
    let title: String
    let category: JunkCategory?
    let measurement: StorageMeasurement
    let disposition: StorageDisposition
    let reason: String
    let sharedBlocks: Bool
    let identity: FileIdentity?
}

struct DockerStorageRow: Identifiable, Sendable {
    var id: String { type }
    var displayName: String {
        switch type {
        case "Images": return "Imagens"
        case "Containers": return "Containers"
        case "Local Volumes": return "Volumes locais"
        case "Build Cache": return "Cache de builds"
        default: return type
        }
    }
    let type: String
    let count: String
    let active: String
    let size: String
    let reclaimable: String
}

struct SimulatorRuntimeRow: Identifiable, Sendable {
    let id: String
    let version: String
    let sizeBytes: Int64
    let lastUsed: String
}

struct StorageReport: Sendable {
    var findings: [StorageFinding] = []
    var issues: [String] = []
    var simulatorRuntimes: [SimulatorRuntimeRow] = []
    var simulatorNote = "Runtimes ainda não consultados."
    var dockerRows: [DockerStorageRow] = []
    var dockerInventory: DockerInventory?
    var dockerNote: String = "Docker ainda não consultado."
    var freeBytes: Int64 = 0
    var scannedAt = Date()
    // Inventory data and APFS clones are never added to the estimate of cleanup candidates.
    var candidateMeasuredBytes: Int64 {
        findings.filter { $0.disposition == .candidate && !$0.sharedBlocks }.reduce(0) { $0 + $1.measurement.allocatedBytes }
    }
    var junkItems: [JunkItem] {
        findings.compactMap { item in
            guard let category = item.category else { return nil }
            return JunkItem(url: item.url, name: item.title, category: category,
                            sizeBytes: item.measurement.allocatedBytes,
                            isRunningApp: item.disposition == .inUse,
                            note: "\(item.disposition.rawValue): \(item.reason)",
                            isSelected: item.disposition == .candidate && !item.sharedBlocks,
                            canClean: item.disposition.allowsSelection,
                            sharedBlocks: item.sharedBlocks, identity: item.identity)
        }
    }
}

// Inventory stays visible independently of whether an item can be cleaned.
enum StorageEnvironment: String, CaseIterable, Identifiable {
    case chrome = "Chrome"
    case docker = "Docker"
    case xcode = "Xcode"
    case android = "Android"
    case other = "Outras ferramentas"
    var id: String { rawValue }

    static func classify(_ item: StorageFinding, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> StorageEnvironment? {
        if item.category == .browserClones { return .chrome }
        let groups: [(StorageEnvironment, [String])] = [
            (.docker, ["Library/Containers/com.docker.docker", "Library/Group Containers/group.com.docker", "Library/Application Support/com.docker.install", "Library/Caches/com.docker.docker"]),
            (.xcode, ["Library/Developer/Xcode", "Library/Developer/CoreSimulator", "Library/Caches/com.apple.dt.Xcode"]),
            (.android, [".android", ".gradle", "Library/Android", "Library/Caches/Google/AndroidStudio"])
        ]
        for (group, paths) in groups {
            if paths.contains(where: { StoragePaths.contains(home.appendingPathComponent($0).path, item.url.path) }) { return group }
        }
        if StoragePaths.contains("/opt/homebrew/share/android-commandlinetools", item.url.path) { return .android }
        if item.category == .devCaches || item.category == .dotCache ||
            StoragePaths.contains(home.appendingPathComponent("Library/pnpm/store").path, item.url.path) ||
            StoragePaths.contains(home.appendingPathComponent("Library/Application Support/Claude/vm_bundles").path, item.url.path) { return .other }
        return nil
    }
}

extension StorageReport {
    func findings(in environment: StorageEnvironment) -> [StorageFinding] {
        findings.filter { StorageEnvironment.classify($0) == environment }
    }
}
