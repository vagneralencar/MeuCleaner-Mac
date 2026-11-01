import Foundation

struct StorageGrowth: Identifiable, Sendable {
    let id: String
    let title: String
    let delta: Int64
}
struct StorageSnapshot: Codable, Sendable {
    let measurementVersion: Int
    let date: Date
    let sizes: [String: Int64]
    init(report: StorageReport) {
        measurementVersion = 2
        date = report.scannedAt
        sizes = Dictionary(uniqueKeysWithValues: report.findings.filter { $0.measurement.complete && !$0.sharedBlocks }
            .map { ($0.id, $0.measurement.allocatedBytes) })
    }
    func growth(in report: StorageReport) -> [StorageGrowth] {
        report.findings.compactMap { item in
            guard item.measurement.complete, !item.sharedBlocks, let old = sizes[item.id], item.measurement.allocatedBytes > old else { return nil }
            return StorageGrowth(id: item.id, title: item.title, delta: item.measurement.allocatedBytes - old)
        }.sorted { $0.delta > $1.delta }
    }
}
enum StorageHistory {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MeuCleaner/storage-snapshot.json")
    }
    static func update(_ report: StorageReport, at url: URL = url) -> (Date?, [StorageGrowth], String?) {
        let decoded = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(StorageSnapshot.self, from: $0) }
        let old = decoded?.measurementVersion == 2 ? decoded : nil
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(StorageSnapshot(report: report)).write(to: url, options: .atomic)
            return (old?.date, old?.growth(in: report) ?? [], nil)
        } catch { return (old?.date, old?.growth(in: report) ?? [], "Histórico não salvo; comparação pode ficar desatualizada.") }
    }
}
