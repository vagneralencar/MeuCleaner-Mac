import Foundation

struct DockerImageCandidate: Identifiable, Sendable {
    let id: String
    let names: [String]
    let size: Int64
    let containers: Int
    var title: String { names.isEmpty ? String(id.prefix(24)) : names.joined(separator: ", ") }
    var canRemove: Bool { containers == 0 }
}
struct DockerCacheCandidate: Identifiable, Sendable {
    let id: String
    let inUse: Bool
    let lastUsed: Date?
    func eligible(at now: Date = Date()) -> Bool {
        !inUse && lastUsed.map { now.timeIntervalSince($0) > 86400 } == true
    }
}
struct DockerInventory: Sendable {
    let socket: String
    let daemonID: String
    let images: [DockerImageCandidate]
    let caches: [DockerCacheCandidate]
    var oldCaches: [DockerCacheCandidate] { caches.filter { $0.eligible() } }
}

struct DockerMaintenance {
    typealias Transport = (String, String, String) throws -> Data
    let socket: String
    let transport: Transport

    init(socket: String, transport: @escaping Transport = DockerMaintenance.request) {
        self.socket = socket; self.transport = transport
    }
    static func localSocket() throws -> String {
        let candidates = ["/Applications/Docker.app/Contents/Resources/bin/docker", "/opt/homebrew/bin/docker", "/usr/local/bin/docker"]
        guard let cli = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { throw failure("Docker CLI não encontrado.") }
        let result = InspectionCommand.run(cli, ["context", "inspect", "desktop-linux", "--format", "{{json .Endpoints.docker.Host}}"], timeout: 8)
        guard result.succeeded, let data = result.output.data(using: .utf8),
              let endpoint = try? JSONDecoder().decode(String.self, from: data),
              let socket = validatedSocket(endpoint) else { throw failure("O destino Docker local não pôde ser validado. Limpeza bloqueada.") }
        return socket
    }
    static func validatedSocket(_ endpoint: String) -> String? {
        let allowed = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".docker/run/docker.sock").path, "/var/run/docker.sock"]
        guard endpoint.hasPrefix("unix://") else { return nil }
        let path = String(endpoint.dropFirst(7))
        return allowed.contains(path) ? path : nil
    }
    static func failure(_ message: String) -> SafetyViolationError { .unsafeRemoval(message) }
    static func request(socket: String, method: String, route: String) throws -> Data {
        // Bypass shell, curl config, proxies and buildx's possibly remote selected builder.
        let seconds = method == "GET" ? 15 : 90
        let result = InspectionCommand.run("/usr/bin/curl", ["--disable", "--silent", "--show-error", "--fail", "--max-time", String(seconds), "--unix-socket", socket, "--noproxy", "*", "--request", method, "--url", "http://localhost" + route], timeout: TimeInterval(seconds + 2))
        guard result.succeeded, let data = result.output.data(using: .utf8) else {
            throw failure("Docker não confirmou a operação. Atualize a análise; uma falha ou tempo limite não confirma remoção nem ausência de dados.")
        }
        return data
    }
    func object(_ method: String, _ route: String) throws -> [String: Any] {
        let data = try transport(socket, method, route)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw Self.failure("Resposta Docker incompleta.") }
        return value
    }
    func daemonID() throws -> String {
        guard let id = try object("GET", "/info")["ID"] as? String, !id.isEmpty else { throw Self.failure("Identidade do Docker não verificada.") }
        return id
    }
    func inventory() throws -> DockerInventory {
        let id = try daemonID()
        let data = try object("GET", "/system/df")
        guard let images = data["Images"] as? [[String: Any]], let caches = data["BuildCache"] as? [[String: Any]] else { throw Self.failure("Inventário Docker incompleto.") }
        var rows: [DockerImageCandidate] = []
        for image in images {
            guard let imageID = image["Id"] as? String, Self.validImageID(imageID),
                  let size = image["Size"] as? NSNumber, let containers = image["Containers"] as? NSNumber else { throw Self.failure("Imagem Docker sem identificação ou uso verificável.") }
            rows.append(DockerImageCandidate(id: imageID, names: (image["RepoTags"] as? [String] ?? []).sorted(), size: size.int64Value, containers: containers.intValue))
        }
        let cacheRows = try caches.map { cache -> DockerCacheCandidate in
            guard let cacheID = cache["ID"] as? String, cacheID.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil, let inUse = cache["InUse"] as? Bool else { throw Self.failure("Uso de cache Docker não verificado.") }
            let raw = cache["LastUsedAt"] as? String
            return DockerCacheCandidate(id: cacheID, inUse: inUse, lastUsed: raw.flatMap(Self.date))
        }
        return DockerInventory(socket: socket, daemonID: id, images: rows.sorted { $0.size > $1.size }, caches: cacheRows)
    }
    static func date(_ raw: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }
    static func validImageID(_ id: String) -> Bool { id.range(of: "^sha256:[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func route(_ path: String, query: [String: String]) -> String {
        var parts = URLComponents(); parts.path = path
        parts.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.string!
    }
    func verify(_ expected: DockerInventory) throws {
        guard socket == expected.socket, try daemonID() == expected.daemonID else { throw Self.failure("O destino Docker mudou desde a revisão. Analise novamente.") }
    }
    func removeImage(_ image: DockerImageCandidate, expected: DockerInventory) throws -> String {
        guard image.canRemove, Self.validImageID(image.id) else { throw Self.failure("Imagem em uso ou não verificada.") }
        try verify(expected)
        let current = try object("GET", "/images/\(image.id)/json")
        guard current["Id"] as? String == image.id, (current["RepoTags"] as? [String] ?? []).sorted() == image.names.sorted() else { throw Self.failure("A imagem ou suas tags mudaram; preservada.") }
        let filters = String(data: try JSONSerialization.data(withJSONObject: ["ancestor": [image.id]]), encoding: .utf8)!
        let data = try transport(socket, "GET", Self.route("/containers/json", query: ["all": "1", "filters": filters]))
        guard let containers = try JSONSerialization.jsonObject(with: data) as? [[String: Any]], containers.isEmpty else { throw Self.failure("Um container, inclusive parado, referencia esta imagem. Preservada.") }
        // Docker rejects a concurrent new reference; never force removal or delete parents.
        let removed = try transport(socket, "DELETE", Self.route("/images/" + image.id, query: ["force": "false", "noprune": "true"]))
        guard let results = try JSONSerialization.jsonObject(with: removed) as? [[String: Any]], results.contains(where: { $0["Deleted"] as? String == image.id }) else { throw Self.failure("A remoção integral não foi confirmada. Atualize a análise.") }
        return "Imagem removida pelo Docker. Pode exigir novo download ou build."
    }
    func pruneCache(expected: DockerInventory) throws -> String {
        try verify(expected)
        let current = try inventory()
        let selected = Set(expected.oldCaches.map(\.id))
        let eligible = current.oldCaches.filter { selected.contains($0.id) }
        guard !eligible.isEmpty else { return "Nenhum cache antigo sem uso permaneceu elegível; nada foi apagado." }
        let filters = String(data: try JSONSerialization.data(withJSONObject: ["id": eligible.map(\.id), "until": ["24h"], "inuse": ["false"]]), encoding: .utf8)!
        let result = try object("POST", Self.route("/build/prune", query: ["all": "false", "filters": filters]))
        guard let bytes = result["SpaceReclaimed"] as? NSNumber else { throw Self.failure("Docker não confirmou o resultado da limpeza.") }
        return "Docker informou \(ByteFormatter.string(from: bytes.int64Value)) recuperados internamente. O espaço livre do Mac pode variar de forma diferente."
    }
}
