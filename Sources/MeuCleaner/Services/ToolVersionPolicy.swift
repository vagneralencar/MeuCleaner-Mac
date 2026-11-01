import Foundation

struct ToolVersionStore {
    let root: URL
    let currentLink: URL
    let title: String

    var currentEntry: URL? {
        let fm = FileManager.default
        guard (try? currentLink.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true,
              fm.fileExists(atPath: currentLink.path) else { return nil }
        let resolved = currentLink.resolvingSymlinksInPath()
        guard StoragePaths.contains(root.path, resolved.path), resolved != root else { return nil }
        let relative = String(resolved.path.dropFirst(root.path.count + 1))
        guard let first = relative.split(separator: "/").first else { return nil }
        return root.appendingPathComponent(String(first))
    }

    func isOldEntry(_ url: URL) -> Bool {
        guard url.deletingLastPathComponent() == root,
              url.standardizedFileURL == url.resolvingSymlinksInPath(),
              let current = currentEntry, current != url,
              url.lastPathComponent.first?.isNumber == true,
              current.lastPathComponent.first?.isNumber == true else { return false }
        return url.lastPathComponent.compare(current.lastPathComponent, options: .numeric) == .orderedAscending
    }

    static func stores(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [ToolVersionStore] {
        [ToolVersionStore(root: home.appendingPathComponent(".codex/packages/standalone/releases"), currentLink: home.appendingPathComponent(".codex/packages/standalone/current"), title: "Codex CLI"),
         ToolVersionStore(root: home.appendingPathComponent(".local/share/cursor-agent/versions"), currentLink: home.appendingPathComponent(".local/bin/cursor-agent"), title: "Cursor Agent"),
         ToolVersionStore(root: home.appendingPathComponent(".local/share/claude/versions"), currentLink: home.appendingPathComponent(".local/bin/claude"), title: "Claude CLI")]
    }

    static func blocker(for url: URL) -> String? {
        for store in stores() where StoragePaths.contains(store.root.path, url.path) || StoragePaths.contains(url.path, store.root.path) {
            if !store.isOldEntry(url) { return "Versão atual, recente ou não verificável de \(store.title); preservada." }
        }
        return nil
    }
}
