import Foundation

struct CleanupRequest: Identifiable {
    enum Target {
        case files([StorageFinding])
        case images(DockerInventory)
        case buildCache(DockerInventory)
    }
    let id = UUID()
    let title: String
    let target: Target
    var initialSelection: Set<String> = []
}
struct CleanupResultRow: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let success: Bool
    let message: String
}
struct CleanupOutcome: Sendable {
    var rows: [CleanupResultRow] = []
    var freeBefore: Int64 = 0
    var freeAfter: Int64 = 0
    var note: String = "A variação do espaço livre também depende de outros aplicativos e de blocos APFS compartilhados."
}

extension StorageFinding {
    var canReviewRemoval: Bool { (category != nil || explicitRemovalConsequence != nil) && measurement.complete && disposition.allowsSelection && identity != nil }
}
