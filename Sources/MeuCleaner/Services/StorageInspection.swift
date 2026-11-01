import Foundation
import Darwin

struct InspectionCommandResult: Sendable {
    var output: String = ""
    var error: String = ""
    var exitCode: Int32 = -1
    var timedOut = false
    var succeeded: Bool { exitCode == 0 && !timedOut }
}

enum InspectionCommand {
    // File-backed output avoids pipe deadlocks, including a verbose or stalled Docker daemon.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15) -> InspectionCommandResult {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("MeuCleaner-inspection-\(UUID())")
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: directory) }
            let outURL = directory.appendingPathComponent("stdout")
            let errURL = directory.appendingPathComponent("stderr")
            fm.createFile(atPath: outURL.path, contents: nil)
            fm.createFile(atPath: errURL.path, contents: nil)
            let out = try FileHandle(forWritingTo: outURL)
            let err = try FileHandle(forWritingTo: errURL)
            defer { try? out.close(); try? err.close() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            var environment = ProcessInfo.processInfo.environment
            environment["LC_ALL"] = "C"
            environment["GIT_OPTIONAL_LOCKS"] = "0"
            process.environment = environment
            let finished = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in finished.signal() }
            try process.run()
            let timedOut = finished.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                if finished.wait(timeout: .now() + 0.5) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = finished.wait(timeout: .now() + 1)
                }
            }
            func read(_ url: URL) -> String {
                guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
                defer { try? handle.close() }
                return String(decoding: (try? handle.read(upToCount: 16 * 1024 * 1024)) ?? Data(), as: UTF8.self)
            }
            let tooLarge = [outURL, errURL].contains {
                ((try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) >= 16 * 1024 * 1024
            }
            return InspectionCommandResult(output: read(outURL), error: tooLarge ? "Saída excedeu o limite de leitura." : read(errURL), exitCode: timedOut || tooLarge ? -1 : process.terminationStatus, timedOut: timedOut)
        } catch {
            return InspectionCommandResult(error: error.localizedDescription)
        }
    }
}

public struct FileIdentity: Hashable, Sendable {
    let device: Int32
    let inode: UInt64
    static func read(_ url: URL) -> FileIdentity? {
        var value = stat()
        guard lstat(url.path, &value) == 0 else { return nil }
        return FileIdentity(device: value.st_dev, inode: value.st_ino)
    }
}

struct StorageMeasurement: Sendable {
    var allocatedBytes: Int64 = 0
    var logicalBytes: Int64 = 0
    var complete = true
    var issues: [String] = []
    var containsProtectedContent = false
}

enum StoragePaths {
    static func normalized(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
    }
    static func contains(_ parent: String, _ child: String) -> Bool {
        child == parent || child.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
    static func sensitiveName(_ name: String) -> Bool {
        let name = name.lowercased()
        return SafetyGuard.protectedFileNames.contains(name) || name.hasPrefix(".env.") || [".git", ".hg", ".svn"].contains(name)
    }
    static func repositoryAncestor(of url: URL) -> URL? {
        var current = url.standardizedFileURL
        while current.path != "/" {
            if [".git", ".hg", ".svn"].contains(current.lastPathComponent) { return current.deletingLastPathComponent() }
            if [".git", ".hg", ".svn"].contains(where: { FileManager.default.fileExists(atPath: current.appendingPathComponent($0).path) }) { return current }
            current.deleteLastPathComponent()
        }
        return nil
    }
}

enum StorageMeter {
    // Counts hidden files and deep trees, deduplicates hard links, never follows symlinks/mounts.
    // Allocated size still is NOT exclusive/reclaimable size on APFS.
    static func measure(_ url: URL, maxEntries: Int = 500_000, timeLimit: TimeInterval = 20) -> StorageMeasurement {
        var result = StorageMeasurement()
        var seen = Set<FileIdentity>()
        var rootStat = stat()
        guard lstat(url.path, &rootStat) == 0 else {
            result.complete = false; result.issues = ["Não foi possível ler \(url.path)"]; return result
        }
        let started = Date()
        func include(_ path: URL) -> Bool {
            var s = stat()
            guard lstat(path.path, &s) == 0 else {
                result.complete = false; result.issues.append("Sem acesso: \(path.path)"); return false
            }
            if StoragePaths.sensitiveName(path.lastPathComponent) { result.containsProtectedContent = true }
            guard s.st_dev == rootStat.st_dev else {
                result.complete = false; result.issues.append("Volume montado preservado: \(path.path)"); return false
            }
            if s.st_mode & S_IFMT == S_IFLNK { return false }
            let identity = FileIdentity(device: s.st_dev, inode: s.st_ino)
            if seen.insert(identity).inserted {
                result.allocatedBytes += Int64(s.st_blocks) * 512
                if s.st_mode & S_IFMT == S_IFREG { result.logicalBytes += s.st_size }
            }
            return true
        }
        guard include(url), rootStat.st_mode & S_IFMT == S_IFDIR else { return result }
        guard let iterator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [], errorHandler: { path, _ in
            result.complete = false
            if result.issues.count < 8 { result.issues.append("Sem acesso: \(path.path)") }
            return true
        }) else {
            result.complete = false; result.issues.append("Pasta não pôde ser enumerada: \(url.path)"); return result
        }
        var count = 0
        while let child = iterator.nextObject() as? URL {
            count += 1
            if count > maxEntries || Date().timeIntervalSince(started) > timeLimit || Task.isCancelled {
                result.complete = false; result.issues.append("Leitura parcial: limite de tempo/arquivos ou cancelamento em \(url.path)"); break
            }
            if !include(child) {
                // Foundation does not descend into symlinks. Calling skipDescendants
                // on one can skip the following real directory (e.g. Versions in a framework).
                var childStat = stat()
                if lstat(child.path, &childStat) == 0 && childStat.st_mode & S_IFMT == S_IFDIR {
                    iterator.skipDescendants()
                }
            }
        }
        return result
    }
}

struct FileUsageSnapshot: Sendable {
    var openPaths: Set<String> = []
    var executablePaths: [String] = []
    var applicationIdentifiers: Set<String> = []
    var mountedPaths: Set<String> = []
    var issues: [String] = []
    var verified: Bool { issues.isEmpty }

    static func capture() -> FileUsageSnapshot {
        let files = InspectionCommand.run("/usr/sbin/lsof", ["-n", "-P", "-F0pcn"], timeout: 20)
        let processes = InspectionCommand.run("/bin/ps", ["-axo", "comm="], timeout: 8)
        let mounts = InspectionCommand.run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 10)
        return parse(files: files, processes: processes, mounts: mounts)
    }

    static func parse(files: InspectionCommandResult, processes: InspectionCommandResult, mounts: InspectionCommandResult) -> FileUsageSnapshot {
        var result = FileUsageSnapshot()
        if !files.succeeded || !files.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !files.output.contains("\0") {
            result.issues.append("Não foi possível verificar todos os arquivos abertos. Limpeza bloqueada até uma nova verificação.")
        } else {
            for raw in files.output.split(separator: "\0", omittingEmptySubsequences: true) {
                let field = raw.drop(while: { $0 == "\n" })
                if field.hasPrefix("n/") { result.openPaths.insert(StoragePaths.normalized(String(field.dropFirst()))) }
            }
        }
        if processes.succeeded && !processes.output.isEmpty {
            result.executablePaths = processes.output.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
        } else { result.issues.append("Não foi possível verificar os processos ativos.") }
        let appPaths = Set(result.executablePaths.compactMap { path -> String? in
            guard let range = path.range(of: ".app/") else { return nil }
            return String(path[..<range.lowerBound]) + ".app"
        })
        result.applicationIdentifiers = Set(appPaths.compactMap { Bundle(url: URL(fileURLWithPath: $0))?.bundleIdentifier?.lowercased() })
        if mounts.succeeded, let data = mounts.output.data(using: .utf8),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let images = plist["images"] as? [[String: Any]] {
            for image in images {
                if let path = image["image-path"] as? String { result.mountedPaths.insert(StoragePaths.normalized(path)) }
                for entity in image["system-entities"] as? [[String: Any]] ?? [] {
                    if let path = entity["mount-point"] as? String { result.mountedPaths.insert(StoragePaths.normalized(path)) }
                }
            }
        } else { result.issues.append("Não foi possível verificar as imagens de disco montadas.") }
        return result
    }

    func blocker(for url: URL) -> String? {
        guard verified else { return issues.first }
        let path = StoragePaths.normalized(url.path)
        if openPaths.contains(where: { StoragePaths.contains(path, $0) }) { return "Arquivos abertos por um processo." }
        if mountedPaths.contains(where: { StoragePaths.contains(path, $0) || StoragePaths.contains($0, path) }) { return "Imagem de disco ou volume montado." }
        if executablePaths.contains(where: { StoragePaths.contains(path, StoragePaths.normalized($0)) }) { return "Executável em uso." }
        let lower = path.lowercased()
        if let range = lower.range(of: "/library/caches/") {
            let cacheName = String(lower[range.upperBound...].split(separator: "/").first ?? "")
            if applicationIdentifiers.contains(where: { cacheName == $0 || cacheName.hasPrefix($0 + ".") }) {
                return "Aplicativo proprietário do cache está aberto."
            }
        }
        if lower.contains("/developer/xcode/") || lower.contains("swiftpm") || lower.contains("/coresimulator/caches") {
            if executablePaths.contains(where: { $0.contains("/Xcode.app/") || $0.contains("SWBBuildService") || $0.hasSuffix("/swift-frontend") }) { return "Xcode ou compilação Swift em execução." }
        }
        if lower.contains("/.gradle/") && executablePaths.contains(where: { $0.hasSuffix("/java") || $0.lowercased().contains("gradle") }) { return "Java/Gradle em execução." }
        if lower.contains("sparkle") || lower.contains("shipit") || lower.contains("/com.openai.codex") || lower.contains("/com.steipete.codexbar") {
            if executablePaths.contains(where: { $0.contains("Autoupdate") || $0.contains("/Updater.app/") || $0.hasSuffix("/ShipIt") }) { return "Atualizador de aplicativos ativo; cache preservado." }
        }
        if lower.contains("com.docker.install") || lower.contains("dockerdesktopupdates") { return "Instalação/atualização Docker: revisar no Docker Desktop." }
        return nil
    }
}

enum ChromeClonePolicy {
    static var root: URL {
        FileManager.default.temporaryDirectory.resolvingSymlinksInPath().deletingLastPathComponent()
            .appendingPathComponent("X/com.google.Chrome.code_sign_clone")
    }
    static func isValid(_ url: URL, root: URL = ChromeClonePolicy.root) -> Bool {
        let url = url.standardizedFileURL
        guard url.deletingLastPathComponent() == root.standardizedFileURL,
              url == url.resolvingSymlinksInPath(),
              url.lastPathComponent.range(of: "^code_sign_clone\\.[A-Za-z0-9]{6}$", options: .regularExpression) != nil else { return false }
        let bundle = url.appendingPathComponent("Google Chrome.app.bundle")
        guard bundle == bundle.resolvingSymlinksInPath(),
              let data = try? Data(contentsOf: bundle.appendingPathComponent("Contents/Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return plist["CFBundleIdentifier"] as? String == "com.google.Chrome"
    }
}

struct StorageDirectoryListing {
    let urls: [URL]
    let issue: String?
}

enum StorageDirectory {
    // A GUI app can otherwise block inside open() while macOS waits for a TCC prompt.
    // Keep permission-gated enumeration in a bounded helper and continue the other scans.
    static func list(_ url: URL) -> StorageDirectoryListing {
        let result = InspectionCommand.run("/usr/bin/find", [url.path, "-mindepth", "1", "-maxdepth", "1", "-print0"], timeout: 6)
        guard result.succeeded, result.error.isEmpty else {
            return StorageDirectoryListing(urls: [], issue: "Não verificado (permissão, erro ou tempo limite): \(url.path)")
        }
        let paths = result.output.split(separator: "\0").map { URL(fileURLWithPath: String($0)) }
        guard paths.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL == url.standardizedFileURL }) else {
            return StorageDirectoryListing(urls: [], issue: "Listagem inesperada, pasta preservada: \(url.path)")
        }
        return StorageDirectoryListing(urls: paths, issue: nil)
    }
}
