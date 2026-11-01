import Foundation

struct IntelligentStorageScanner {
    let home: URL
    let cloneRoot: URL
    let usage: FileUsageSnapshot
    private(set) var report = StorageReport()
    private var seen = Set<String>()

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser, cloneRoot: URL = ChromeClonePolicy.root, usage: FileUsageSnapshot) {
        self.home = home; self.cloneRoot = cloneRoot; self.usage = usage
        report.issues = usage.issues
        report.freeBytes = Self.freeSpace(at: home)
    }

    static func freeSpace(at url: URL) -> Int64 {
        let values = try? FileManager.default.attributesOfFileSystem(forPath: url.path)
        return (values?[.systemFreeSize] as? NSNumber)?.int64Value ?? 0
    }

    static func scan() -> StorageReport {
        var scanner = IntelligentStorageScanner(usage: .capture())
        scanner.scanFiles()
        scanner.scanDocker()
        scanner.scanSimulatorRuntimes()
        scanner.report.findings.sort { $0.measurement.allocatedBytes > $1.measurement.allocatedBytes }
        scanner.report.issues = Array(Set(scanner.report.issues)).sorted()
        return scanner.report
    }

    mutating func children(_ url: URL) -> [URL] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        if ["Downloads", ".Trash", "Library/Mail", "Library/Messages"].contains(where: { home.appendingPathComponent($0).standardizedFileURL == url.standardizedFileURL }) {
            let listing = StorageDirectory.list(url)
            if let issue = listing.issue { report.issues.append(issue) }
            return listing.urls
        }
        do { return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) }
        catch { report.issues.append("Sem acesso a \(url.path): \(error.localizedDescription)"); return [] }
    }

    mutating func append(_ url: URL, title: String, category: JunkCategory?, review: Bool = false, preserve: String? = nil, shared: Bool = false) {
        guard FileManager.default.fileExists(atPath: url.path), seen.insert(url.standardizedFileURL.path).inserted else { return }
        let measurement = StorageMeter.measure(url)
        report.issues.append(contentsOf: measurement.issues)
        guard measurement.allocatedBytes > 0 || !measurement.complete else { return }
        var disposition: StorageDisposition = review ? .review : .candidate
        var reason = review ? "Revisão manual; tamanho não garante espaço recuperável." : "Recriável; sem uso detectado. Uso será conferido novamente ao limpar."
        if let preserve {
            disposition = .protected; reason = preserve
        } else if url.standardizedFileURL != url.resolvingSymlinksInPath() {
            disposition = .protected; reason = "Link simbólico preservado."
        } else if !measurement.complete {
            disposition = .unverified; reason = "Leitura parcial; não considerar como vazio ou seguro."
        } else if measurement.containsProtectedContent || StoragePaths.repositoryAncestor(of: url) != nil {
            disposition = .protected; reason = "Contém projeto, repositório ou arquivo sensível."
        } else if !usage.verified {
            disposition = .unverified; reason = "A verificação de uso não foi concluída."
        } else if let blocker = usage.blocker(for: url) {
            disposition = .inUse; reason = blocker
        } else if let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(modified) < 3600 {
            disposition = .review; reason = "Modificado na última hora; pode pertencer a uma tarefa recente."
        }
        if shared && disposition.allowsSelection {
            disposition = .review; reason = "Cópia temporária do Chrome. Blocos APFS podem ser compartilhados; recuperação desconhecida."
        }
        report.findings.append(StorageFinding(url: url, title: title, category: category, measurement: measurement,
                                              disposition: disposition, reason: reason, sharedBlocks: shared, identity: .read(url)))
    }

    mutating func scanFiles() {
        for child in children(home.appendingPathComponent("Library/Caches")) {
            let name = child.lastPathComponent.lowercased()
            guard !name.hasPrefix("com.apple."), !SafetyGuard.protectedCacheIdentifiers.contains(where: { name.contains($0) }) else { continue }
            append(child, title: child.lastPathComponent, category: .userCaches,
                   review: name.contains("homebrew") || name.contains("dotslash"))
        }
        for child in children(home.appendingPathComponent("Library/Logs")) {
            append(child, title: child.lastPathComponent, category: .userLogs)
        }
        for child in children(home.appendingPathComponent("Library/Developer/Xcode/DerivedData")) {
            append(child, title: "Xcode · \(child.lastPathComponent)", category: .xcode)
        }
        let cachePaths: [(String, String)] = [
            (".npm/_cacache", "npm"), (".gradle/caches", "Gradle"),
            (".bun/install/cache", "Bun"), (".cargo/registry/cache", "Cargo"),
            ("Library/Caches/com.apple.dt.Xcode", "Xcode"),
            ("Library/Developer/CoreSimulator/Caches", "Cache de simuladores")
        ]
        for (path, title) in cachePaths { append(home.appendingPathComponent(path), title: title, category: .devCaches) }
        for child in children(home.appendingPathComponent(".cache")) {
            let keep = ["codex-runtimes", "huggingface", "lm-studio"].contains(child.lastPathComponent)
            append(child, title: "~/.cache/\(child.lastPathComponent)", category: .dotCache, review: true,
                   preserve: keep ? "Runtime ou modelos instalados; preservar funcionalidades e downloads." : nil)
        }
        for child in children(cloneRoot) {
            guard ChromeClonePolicy.isValid(child, root: cloneRoot) else {
                report.issues.append("Cópia Chrome não reconhecida, preservada: \(child.path)"); continue
            }
            append(child, title: "Chrome · \(child.lastPathComponent)", category: .browserClones, review: true, shared: true)
        }
        for child in children(home.appendingPathComponent("Downloads")) {
            if ["part", "crdownload", "download", "tmp"].contains(child.pathExtension.lowercased()) {
                append(child, title: child.lastPathComponent, category: .incompleteDownloads, review: true)
            } else if ["dmg", "pkg"].contains(child.pathExtension.lowercased()) {
                append(child, title: "Instalador · \(child.lastPathComponent)", category: .installers, review: true)
            }
        }
        let inventories: [(String, String, String)] = [
            ("Library/Developer/CoreSimulator/Devices", "Dados dos simuladores iOS", "Desligado não significa descartável: contém aplicativos e dados de testes."),
            (".android/avd", "Emuladores Android", "Contém dados e snapshots de emuladores; preservar mesmo quando desligados."),
            ("Library/Developer/Xcode/Archives", "Arquivos de distribuição Xcode", "Archives e símbolos de distribuição preservados."),
            ("Library/Developer/Xcode/iOS DeviceSupport", "Suporte a dispositivos iOS", "Componentes de desenvolvimento instalados; revisar no Xcode."),
            ("Library/Containers/com.docker.docker/Data", "Disco e dados Docker", "Não apagar Docker.raw: contém containers, imagens e bancos de dados."),
            ("Library/Application Support/Claude/vm_bundles", "Máquina virtual Claude", "Dados da máquina virtual; não é cache descartável."),
            ("Library/Application Support/com.docker.install", "Instalação Docker pendente", "Pode conter uma atualização diferente da instalada. Revisar no Docker Desktop."),
            ("Library/pnpm/store", "Store pnpm", "Usar o gerenciador para identificar dependências sem uso; preservar o store completo."),
            ("Library/Android/sdk", "SDK Android", "Ferramentas e imagens instaladas; revisar no gerenciador do SDK.")
        ]
        for (path, title, reason) in inventories { append(home.appendingPathComponent(path), title: title, category: nil, preserve: reason) }
        let sdk = URL(fileURLWithPath: "/opt/homebrew/share/android-commandlinetools")
        append(sdk, title: "SDK Android (Homebrew)", category: nil, preserve: "Componentes instalados; não são todos caches.")
        for store in ToolVersionStore.stores(home: home) {
            for version in children(store.root) where version.lastPathComponent.first?.isNumber == true {
                append(version, title: "\(store.title) · \(version.lastPathComponent)", category: .devCaches, review: true,
                       preserve: store.isOldEntry(version) ? nil : "Versão atual, recente ou não verificável; preservar.")
            }
        }
        scanRepositories()
        // Probe privacy boundaries and report denial rather than presenting an empty folder as clean.
        for path in [".Trash", "Library/Mail", "Library/Messages"] { _ = children(home.appendingPathComponent(path)) }
    }

    mutating func scanRepositories() {
        let fm = FileManager.default
        for name in ["dev", "Developer", "Projects", "Code", "Workspace"] {
            let root = home.appendingPathComponent(name)
            var traversalIssues: [String] = []
            guard fm.fileExists(atPath: root.path), let iterator = fm.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey], options: [.skipsPackageDescendants], errorHandler: { url, _ in traversalIssues.append("Sem acesso ao projeto: \(url.path)"); return true }) else { continue }
            while let url = iterator.nextObject() as? URL {
                if Task.isCancelled { traversalIssues.append("Varredura de projetos cancelada."); break }
                if FileIdentity.read(url)?.device != FileIdentity.read(root)?.device { iterator.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                if values?.isSymbolicLink == true { continue }
                if iterator.level > 4 || ["node_modules", ".build", "target", ".venv"].contains(url.lastPathComponent) {
                    if values?.isDirectory == true { iterator.skipDescendants() }
                    continue
                }
                guard values?.isDirectory == true else { continue }
                guard fm.fileExists(atPath: url.appendingPathComponent(".git").path) else { continue }
                iterator.skipDescendants()
                let status = InspectionCommand.run("/usr/bin/git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", url.path, "status", "--porcelain=v1", "-z"], timeout: 5)
                let note: String
                if status.succeeded {
                    note = status.output.isEmpty ? "Repositório preservado, inclusive commits locais e arquivos ignorados." : "Há alterações pendentes. Projeto, worktree e commits preservados."
                } else { note = "Estado Git não verificado; projeto preservado."; report.issues.append("Git indisponível em \(url.path)") }
                append(url, title: "Projeto · \(url.lastPathComponent)", category: nil, preserve: note)
            }
            report.issues.append(contentsOf: traversalIssues)
        }
    }

    mutating func scanDocker() {
        let candidates = ["/Applications/Docker.app/Contents/Resources/bin/docker", "/opt/homebrew/bin/docker", "/usr/local/bin/docker"]
        guard let docker = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            report.dockerNote = "Docker CLI não encontrado. Nenhum serviço foi iniciado."; return
        }
        // Never prune, start Docker, remove volumes or change a context during inspection.
        let result = InspectionCommand.run(docker, ["--context", "desktop-linux", "system", "df", "--format", "{{json .}}"], timeout: 15)
        guard result.succeeded, let rows = Self.parseDocker(result.output), !rows.isEmpty else {
            report.dockerNote = "Docker local indisponível ou resposta incompleta. Uso não verificado; não é zero."
            report.issues.append(report.dockerNote); return
        }
        report.dockerRows = rows
        do {
            report.dockerInventory = try DockerMaintenance(socket: DockerMaintenance.localSocket()).inventory()
        } catch { report.issues.append("Limpeza Docker bloqueada: \(error.localizedDescription)") }
        report.dockerNote = "Somente leitura, contexto local desktop-linux. 'Recuperável' é a estimativa do Docker e não autoriza apagar volumes ou builds locais."
    }

    mutating func scanSimulatorRuntimes() {
        let result = InspectionCommand.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"], timeout: 12)
        guard result.succeeded, let rows = Self.parseSimulatorRuntimes(result.output) else {
            report.simulatorNote = "Runtimes não verificados: Xcode indisponível, acesso negado ou tempo limite. Nenhum simulador foi apagado."
            report.issues.append(report.simulatorNote)
            return
        }
        report.simulatorRuntimes = rows
        report.simulatorNote = "Inventário somente de leitura. Runtimes, dispositivos e dados de testes são preservados, mesmo se constarem indisponíveis."
    }

    static func parseSimulatorRuntimes(_ text: String) -> [SimulatorRuntimeRow]? {
        guard let data = text.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return nil }
        var rows: [SimulatorRuntimeRow] = []
        for (id, item) in object {
            guard let version = item["version"] as? String, let bytes = item["sizeBytes"] as? NSNumber else { return nil }
            rows.append(SimulatorRuntimeRow(id: id, version: version, sizeBytes: bytes.int64Value, lastUsed: item["lastUsedAt"] as? String ?? "Não informado"))
        }
        return rows.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }

    static func parseDocker(_ text: String) -> [DockerStorageRow]? {
        var rows: [DockerStorageRow] = []
        for line in text.split(separator: "\n") {
            guard let data = String(line).data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["Type"] as? String, let size = object["Size"] as? String,
                  let reclaimable = object["Reclaimable"] as? String,
                  let count = object["TotalCount"], let active = object["Active"] else { return nil }
            rows.append(DockerStorageRow(type: type, count: String(describing: count), active: String(describing: active), size: size, reclaimable: reclaimable))
        }
        return rows.isEmpty ? nil : rows
    }
}
