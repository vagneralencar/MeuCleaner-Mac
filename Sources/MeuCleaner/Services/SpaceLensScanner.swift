import Foundation
import Darwin

enum SpaceLensScanner {
    // Measure one level at a time. Children are expanded on demand, with a bounded
    // total budget, hidden entries included and no traversal of symlinks/mounts.
    static func scan(_ root: URL, timeLimit: TimeInterval = 90) -> (DiskNode, Int) {
        let start = Date()
        let listing = StorageDirectory.list(root)
        var rootStat = stat()
        let readable = lstat(root.path, &rootStat) == 0
        if readable && rootStat.st_mode & S_IFMT != S_IFDIR {
            return (DiskNode(url: root, name: root.lastPathComponent, sizeBytes: 0, isDirectory: false,
                             isComplete: false, issues: ["Escolha uma pasta direta; links não são percorridos."]), 0)
        }
        var issues = listing.issue.map { [$0] } ?? []
        if !readable { issues.append("Não foi possível verificar a pasta.") }
        var nodes: [DiskNode] = []
        var seen = Set<FileIdentity>()
        for url in listing.urls {
            var childStat = stat()
            let exists = lstat(url.path, &childStat) == 0
            let directory = exists && childStat.st_mode & S_IFMT == S_IFDIR
            let remaining = timeLimit - Date().timeIntervalSince(start)
            let measurement: StorageMeasurement
            if !exists || !readable {
                measurement = StorageMeasurement(complete: false, issues: ["Não foi possível ler \(url.path)"])
            } else if childStat.st_dev != rootStat.st_dev {
                measurement = StorageMeasurement(complete: false, issues: ["Outro volume não incluído: \(url.path)"])
            } else if remaining <= 0 {
                measurement = StorageMeasurement(complete: false, issues: ["Tempo de análise excedido: \(url.path)"])
            } else {
                let previouslySeen = seen
                let budget = min(6, remaining)
                if let read = BoundedFilesystemRead.run(key: "map:\(url.path)", timeout: budget, read: {
                    var localSeen = previouslySeen
                    let measured = StorageMeter.measure(url, maxEntries: 500_000, timeLimit: budget, seen: &localSeen)
                    return (measured, localSeen)
                }) {
                    measurement = read.0
                    seen = read.1
                } else {
                    measurement = StorageMeasurement(complete: false, issues: ["Leitura não concluída no prazo ou ainda aguardando o macOS: \(url.path)"])
                }
            }
            nodes.append(DiskNode(url: url, name: url.lastPathComponent, sizeBytes: measurement.allocatedBytes,
                                  isDirectory: directory, isComplete: measurement.complete, issues: measurement.issues))
            issues.append(contentsOf: measurement.issues)
        }
        nodes.sort { $0.sizeBytes > $1.sizeBytes }
        let node = DiskNode(url: root, name: root.lastPathComponent, sizeBytes: nodes.reduce(Int64(rootStat.st_blocks) * 512) { $0 + $1.sizeBytes },
                            isDirectory: true, itemCount: nodes.count, children: nodes,
                            isComplete: issues.isEmpty && nodes.allSatisfy(\.isComplete), issues: Array(Set(issues)).sorted())
        return (node, nodes.count)
    }
}
