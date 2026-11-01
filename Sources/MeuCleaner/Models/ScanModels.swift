import Foundation
import AppKit

// MARK: - Removal Mode (CleanerCore.RemovalMode)

public enum RemovalMode: String, CaseIterable, Identifiable, Sendable {
    case trash = "trash"
    case permanent = "permanent"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .trash: return "Mover para a Lixeira"
        case .permanent: return "Apagar permanentemente"
        }
    }

    public var subtitle: String {
        switch self {
        case .trash: return "Dá para recuperar tudo na Lixeira até você esvaziá-la."
        case .permanent: return "Os itens não passam pela Lixeira e pedem para segurar o botão por 1s."
        }
    }
}

// MARK: - Semantic Version Comparator (CleanerCore.AppVersion)

public enum AppVersion {
    /// Strips leading 'v' or 'V' and trims whitespace/newlines for reliable semantic comparison.
    public static func normalize(_ version: String) -> String {
        var clean = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.lowercased().hasPrefix("v") {
            clean.removeFirst()
        }
        return clean.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let cleanCandidate = normalize(candidate)
        let cleanCurrent = normalize(current)
        guard !cleanCandidate.isEmpty, !cleanCurrent.isEmpty, cleanCandidate != cleanCurrent else {
            return false
        }
        return cleanCandidate.compare(cleanCurrent, options: [.numeric]) == .orderedDescending
    }
}

// MARK: - System Junk Models (CleanerCore.JunkRule)

public enum JunkCategory: String, CaseIterable, Identifiable, Sendable {
    case userCaches = "Caches do usuário"
    case userLogs = "Logs do usuário"
    case xcode = "Lixo do Xcode"
    case devCaches = "Caches de desenvolvimento"
    case dotCache = "Outros caches (~/.cache)"
    case incompleteDownloads = "Downloads incompletos"
    case browserClones = "Cópias temporárias do Chrome"
    case installers = "Instaladores"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .userCaches: return "memorychip"
        case .userLogs: return "doc.text.magnifyingglass"
        case .xcode: return "hammer.fill"
        case .devCaches: return "terminal.fill"
        case .dotCache: return "folder.badge.questionmark"
        case .incompleteDownloads: return "arrow.down.circle.dotted"
        case .browserClones: return "doc.on.doc"
        case .installers: return "opticaldisc"
        }
    }

    public var description: String {
        switch self {
        case .userCaches:
            return "Arquivos temporários que os apps recriam quando precisam."
        case .userLogs:
            return "Registros de atividade e relatórios de falhas dos apps."
        case .xcode:
            return "DerivedData, símbolos de dispositivos e caches do simulador."
        case .devCaches:
            return "Caches de gerenciadores de pacotes: npm, pnpm, Bun, Gradle, Cargo."
        case .dotCache:
            return "Caches de ferramentas de linha de comando. Pode incluir modelos baixados, então revise antes."
        case .incompleteDownloads:
            return "Downloads interrompidos que ficaram na pasta Downloads."
        case .browserClones: return "Cópias do aplicativo; blocos APFS podem ser compartilhados."
        case .installers: return "Pacotes baixados que exigem revisão antes da remoção."
        }
    }

    public var selectedByDefault: Bool {
        switch self {
        case .dotCache, .browserClones, .installers:
            // Per CleanUai's JunkRule.defaults, ~/.cache is unchecked by default for safety
            return false
        default:
            return true
        }
    }
}

public struct JunkItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let category: JunkCategory
    public let sizeBytes: Int64
    public let isRunningApp: Bool
    public let canClean: Bool
    public let sharedBlocks: Bool
    public let identity: FileIdentity?
    public let note: String?
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        category: JunkCategory,
        sizeBytes: Int64,
        isRunningApp: Bool = false,
        note: String? = nil,
        isSelected: Bool? = nil,
        canClean: Bool = true,
        sharedBlocks: Bool = false,
        identity: FileIdentity? = nil
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.category = category
        self.sizeBytes = sizeBytes
        self.isRunningApp = isRunningApp
        self.canClean = canClean && !isRunningApp
        self.sharedBlocks = sharedBlocks
        self.identity = identity
        self.note = note ?? (isRunningApp ? "App aberto" : (category == .dotCache ? "Revisar" : nil))
        if let explicit = isSelected {
            self.isSelected = explicit && self.canClean
        } else {
            self.isSelected = self.canClean && category.selectedByDefault
        }
    }
}

// MARK: - Space Lens Models (CleanerCore.DiskNode)

public struct DiskNode: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeBytes: Int64
    public let isDirectory: Bool
    public let itemCount: Int
    public var children: [DiskNode]
    public var isSelectedForCleanup: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        sizeBytes: Int64,
        isDirectory: Bool,
        itemCount: Int = 1,
        children: [DiskNode] = [],
        isSelectedForCleanup: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.isDirectory = isDirectory
        self.itemCount = itemCount
        self.children = children
        self.isSelectedForCleanup = isSelectedForCleanup
    }
}

// MARK: - Large & Old Models (CleanerCore.FileKind & LargeFileAge)

public enum LargeFileCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "Todos"
    case video = "Vídeos"
    case diskImage = "Imagens de disco"
    case archive = "Compactados"
    case audio = "Áudio"
    case image = "Imagens"
    case document = "Documentos"
    case other = "Outros"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .all: return "tray.full.fill"
        case .video: return "film.fill"
        case .diskImage: return "opticaldiscdrive.fill"
        case .archive: return "doc.zipper"
        case .audio: return "waveform"
        case .image: return "photo.fill"
        case .document: return "doc.richtext.fill"
        case .other: return "doc.fill"
        }
    }

    public static func categorize(url: URL) -> LargeFileCategory {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4", "mov", "mkv", "avi", "webm", "m4v":
            return .video
        case "dmg", "iso", "img", "pkg", "sparseimage", "ipsw":
            return .diskImage
        case "zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst":
            return .archive
        case "mp3", "wav", "flac", "m4a", "aac", "aiff", "ogg":
            return .audio
        case "png", "jpg", "jpeg", "heic", "tiff", "bmp", "gif", "webp", "psd", "raw":
            return .image
        case "pdf", "epub", "pages", "key", "numbers", "docx", "xlsx", "pptx":
            return .document
        default:
            return .other
        }
    }
}

public enum FileAgeFilter: String, CaseIterable, Identifiable, Sendable {
    case any = "Tanto faz"
    case threeMonths = "90 dias"
    case sixMonths = "6 meses"
    case oneYear = "1 ano"

    public var id: String { rawValue }

    public var minimumDays: Int {
        switch self {
        case .any: return 0
        case .threeMonths: return 90
        case .sixMonths: return 180
        case .oneYear: return 365
        }
    }
}

public struct LargeFileItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeBytes: Int64
    public let lastAccessed: Date
    public let category: LargeFileCategory
    public let isInICloud: Bool
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        sizeBytes: Int64,
        lastAccessed: Date,
        category: LargeFileCategory,
        isInICloud: Bool = false,
        isSelected: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.lastAccessed = lastAccessed
        self.category = category
        self.isInICloud = isInICloud
        self.isSelected = isSelected
    }

    public var daysSinceAccess: Int {
        max(0, Calendar.current.dateComponents([.day], from: lastAccessed, to: Date()).day ?? 0)
    }
}

// MARK: - Uninstaller & Leftover Models (CleanerCore.LeftoverKind, LeftoverCaution, UninstallBlocker)

public enum LeftoverKind: String, CaseIterable, Sendable {
    case app = "App"
    case caches = "Caches"
    case cookies = "Cookies"
    case data = "Dados"
    case logs = "Logs"
    case preferences = "Preferências"
    case savedState = "Estado salvo"
    case startup = "Inicialização"
}

public enum LeftoverCaution: String, Sendable {
    case shared = "Compartilhado"
    case systemWide = "Todos os usuários"
}

public enum UninstallBlocker: Equatable, Hashable, Sendable {
    case appleApp
    case runningApp
    case selfApp

    public var badgeText: String {
        switch self {
        case .appleApp: return "App da Apple"
        case .runningApp: return "Encerre o app primeiro"
        case .selfApp: return "Este é o MeuCleaner"
        }
    }

    public func message(for appName: String) -> String {
        switch self {
        case .appleApp:
            return "\(appName) é um app da Apple e não é desinstalado por aqui."
        case .runningApp:
            return "\(appName) está aberto. Encerre antes de desinstalar."
        case .selfApp:
            return "O MeuCleaner não desinstala a si mesmo."
        }
    }
}

public struct AppRelatedFile: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let locationType: String
    public let kind: LeftoverKind
    public let caution: LeftoverCaution?
    public let sizeBytes: Int64
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        locationType: String,
        kind: LeftoverKind = .data,
        caution: LeftoverCaution? = nil,
        sizeBytes: Int64,
        isSelected: Bool = true
    ) {
        self.id = id
        self.url = url
        self.locationType = locationType
        self.kind = kind
        self.caution = caution
        self.sizeBytes = sizeBytes
        self.isSelected = isSelected
    }
}

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let bundleURL: URL
    public let name: String
    public let bundleIdentifier: String
    public let version: String
    public let buildVersion: String?
    public let feedURL: URL?
    public let hasAppStoreReceipt: Bool
    public let appSizeBytes: Int64
    public let lastUsedDate: Date?
    public var relatedFiles: [AppRelatedFile]
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        bundleURL: URL,
        name: String,
        bundleIdentifier: String,
        version: String,
        buildVersion: String? = nil,
        feedURL: URL? = nil,
        hasAppStoreReceipt: Bool = false,
        appSizeBytes: Int64,
        lastUsedDate: Date? = nil,
        relatedFiles: [AppRelatedFile] = [],
        isSelected: Bool = false
    ) {
        self.id = id
        self.bundleURL = bundleURL
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.buildVersion = buildVersion
        self.feedURL = feedURL
        self.hasAppStoreReceipt = hasAppStoreReceipt
        self.appSizeBytes = appSizeBytes
        self.lastUsedDate = lastUsedDate
        self.relatedFiles = relatedFiles
        self.isSelected = isSelected
    }

    public var leftoversSizeBytes: Int64 {
        relatedFiles.reduce(0) { $0 + $1.sizeBytes }
    }

    public var totalSizeBytes: Int64 {
        appSizeBytes + leftoversSizeBytes
    }

    public func uninstallBlocker(runningBundleIDs: Set<String>) -> UninstallBlocker? {
        let lowerID = bundleIdentifier.lowercased()
        if lowerID.contains("meucleaner") || name.lowercased() == "meucleaner" {
            return .selfApp
        }
        if lowerID.hasPrefix("com.apple.") || bundleURL.path.hasPrefix("/System/") {
            return .appleApp
        }
        if runningBundleIDs.contains(lowerID) {
            return .runningApp
        }
        return nil
    }
}

// MARK: - Leftovers (Orphaned Files) Models

public struct OrphanedLeftoverGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let inferredAppName: String
    public let identifierHint: String
    public var files: [AppRelatedFile]
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        inferredAppName: String,
        identifierHint: String,
        files: [AppRelatedFile],
        isSelected: Bool = false
    ) {
        self.id = id
        self.inferredAppName = inferredAppName
        self.identifierHint = identifierHint
        self.files = files
        self.isSelected = isSelected
    }

    public var totalSizeBytes: Int64 {
        files.reduce(0) { $0 + $1.sizeBytes }
    }
}

// MARK: - Trash Models

public struct TrashItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeBytes: Int64
    public let deletedDate: Date?
    public let isDirectory: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        sizeBytes: Int64,
        deletedDate: Date?,
        isDirectory: Bool
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.sizeBytes = sizeBytes
        self.deletedDate = deletedDate
        self.isDirectory = isDirectory
    }
}

// MARK: - App Updater Models (Sparkle + App Store + Homebrew)

public enum UpdateSource: String, Sendable {
    case sparkle = "Sparkle"
    case appStore = "App Store"
    case homebrew = "Homebrew"
}

public struct UpdatableApp: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let bundleIdentifier: String
    public let bundleURL: URL?
    public let currentVersion: String
    public let latestVersion: String
    public let source: UpdateSource
    public let releaseNotes: String
    public let downloadOrStoreURL: URL?
    public let caskToken: String?
    public var isSkipped: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        bundleIdentifier: String,
        bundleURL: URL?,
        currentVersion: String,
        latestVersion: String,
        source: UpdateSource,
        releaseNotes: String,
        downloadOrStoreURL: URL? = nil,
        caskToken: String? = nil,
        isSkipped: Bool = false
    ) {
        self.id = id
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.source = source
        self.releaseNotes = releaseNotes
        self.downloadOrStoreURL = downloadOrStoreURL
        self.caskToken = caskToken
        self.isSkipped = isSkipped
    }
}

// MARK: - Channel 08: Dev & IA Cleaner Models

public enum DevArtifactCategory: String, CaseIterable, Identifiable, Sendable {
    case all = "Todos"
    case nodeModules = "Node.js (node_modules / .next)"
    case pythonVenv = "Python (.venv / venv)"
    case rustSwiftBuild = "Rust & Swift (target / .build)"
    case aiModels = "Modelos de IA (Ollama / HuggingFace / LM Studio)"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .all: return "square.stack.3d.up.fill"
        case .nodeModules: return "shippingbox.fill"
        case .pythonVenv: return "terminal.fill"
        case .rustSwiftBuild: return "hammer.fill"
        case .aiModels: return "brain.head.profile"
        }
    }
}

public struct DevArtifactItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let projectName: String
    public let artifactFolderName: String
    public let category: DevArtifactCategory
    public let sizeBytes: Int64
    public let lastModified: Date
    public var isSelected: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        projectName: String,
        artifactFolderName: String,
        category: DevArtifactCategory,
        sizeBytes: Int64,
        lastModified: Date,
        isSelected: Bool? = nil
    ) {
        self.id = id
        self.url = url
        self.projectName = projectName
        self.artifactFolderName = artifactFolderName
        self.category = category
        self.sizeBytes = sizeBytes
        self.lastModified = lastModified
        // Project artifacts and models require review; never infer safety from age.
        if let explicit = isSelected {
            self.isSelected = explicit
        } else {
            self.isSelected = false // Age alone does not prove that a project artifact is disposable.
        }
    }

    public var daysInactive: Int {
        max(0, Calendar.current.dateComponents([.day], from: lastModified, to: Date()).day ?? 0)
    }
}

// MARK: - Channel 09: Startup & LaunchAgents Models

public enum StartupAgentScope: String, CaseIterable, Identifiable, Sendable {
    case userAgent = "Agente do Usuário (~/Library/LaunchAgents)"
    case globalAgent = "Agente Global (/Library/LaunchAgents)"
    case systemDaemon = "Daemon do Sistema (/Library/LaunchDaemons)"

    public var id: String { rawValue }

    public var shortBadge: String {
        switch self {
        case .userAgent: return "Usuário"
        case .globalAgent: return "Global"
        case .systemDaemon: return "Daemon"
        }
    }
}

public struct StartupAgentItem: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let plistURL: URL
    public let label: String
    public let programPath: String
    public let scope: StartupAgentScope
    public let runAtLoad: Bool
    public let keepAlive: Bool
    public let sizeBytes: Int64
    public var isLoadedInLaunchd: Bool

    public init(
        id: UUID = UUID(),
        plistURL: URL,
        label: String,
        programPath: String,
        scope: StartupAgentScope,
        runAtLoad: Bool,
        keepAlive: Bool,
        sizeBytes: Int64,
        isLoadedInLaunchd: Bool
    ) {
        self.id = id
        self.plistURL = plistURL
        self.label = label
        self.programPath = programPath
        self.scope = scope
        self.runAtLoad = runAtLoad
        self.keepAlive = keepAlive
        self.sizeBytes = sizeBytes
        self.isLoadedInLaunchd = isLoadedInLaunchd
    }

    public var inferredVendorName: String {
        let parts = label.split(separator: ".").map(String.init)
        if parts.count >= 2 {
            let vendor = parts[1]
            return vendor.prefix(1).uppercased() + vendor.dropFirst()
        }
        return label
    }
}

// MARK: - Channel 10: Smart Duplicates Models

public struct DuplicateFileEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let modifiedDate: Date
    public var isSelectedForRemoval: Bool

    public init(
        id: UUID = UUID(),
        url: URL,
        name: String,
        modifiedDate: Date,
        isSelectedForRemoval: Bool = false
    ) {
        self.id = id
        self.url = url
        self.name = name
        self.modifiedDate = modifiedDate
        self.isSelectedForRemoval = isSelectedForRemoval
    }
}

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let hashHex: String
    public let eachFileSizeBytes: Int64
    public var files: [DuplicateFileEntry]

    public init(
        id: UUID = UUID(),
        hashHex: String,
        eachFileSizeBytes: Int64,
        files: [DuplicateFileEntry]
    ) {
        self.id = id
        self.hashHex = hashHex
        self.eachFileSizeBytes = eachFileSizeBytes
        self.files = files
    }

    public var selectedReclaimableBytes: Int64 {
        Int64(files.filter(\.isSelectedForRemoval).count) * eachFileSizeBytes
    }

    public var maxReclaimableBytes: Int64 {
        Int64(max(0, files.count - 1)) * eachFileSizeBytes
    }
}

// MARK: - Trash App Watcher Alert (Vigia da Lixeira)

public struct TrashedAppAlert: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let trashedAppURL: URL
    public let appName: String
    public let bundleIdentifier: String
    public let leftoverFiles: [AppRelatedFile]

    public init(
        id: UUID = UUID(),
        trashedAppURL: URL,
        appName: String,
        bundleIdentifier: String,
        leftoverFiles: [AppRelatedFile]
    ) {
        self.id = id
        self.trashedAppURL = trashedAppURL
        self.appName = appName
        self.bundleIdentifier = bundleIdentifier
        self.leftoverFiles = leftoverFiles
    }

    public var totalLeftoversBytes: Int64 {
        leftoverFiles.reduce(0) { $0 + $1.sizeBytes }
    }
}

// MARK: - Cleanup History & Undo Receipts

public struct TrashReceipt: Identifiable, Sendable {
    public let id: UUID
    public let originalURL: URL
    public let trashURL: URL
    public let date: Date
    public let sizeBytes: Int64
    public let channelTitle: String

    public init(
        id: UUID = UUID(),
        originalURL: URL,
        trashURL: URL,
        date: Date = Date(),
        sizeBytes: Int64,
        channelTitle: String
    ) {
        self.id = id
        self.originalURL = originalURL
        self.trashURL = trashURL
        self.date = date
        self.sizeBytes = sizeBytes
        self.channelTitle = channelTitle
    }
}

public struct CleanupHistoryRecord: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public let date: Date
    public let channelTitle: String
    public let freedBytes: Int64
    public let itemsCount: Int

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        channelTitle: String,
        freedBytes: Int64,
        itemsCount: Int
    ) {
        self.id = id
        self.date = date
        self.channelTitle = channelTitle
        self.freedBytes = freedBytes
        self.itemsCount = itemsCount
    }
}

// MARK: - Byte Formatting Helper

public enum ByteFormatter {
    public static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
