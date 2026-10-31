import Foundation

public enum SafetyViolationError: LocalizedError {
    case protectedSystemPath(String)
    case protectedUserDataPath(String)
    case protectedSecurityCredentials(String)
    case outsideCurrentUserHome(String)
    case selfApplicationProtected(String)

    public var errorDescription: String? {
        switch self {
        case .protectedSystemPath(let path):
            return "Caminho protegido do sistema, não será removido: \(path)"
        case .protectedUserDataPath(let path):
            return "Caminho protegido (Documentos, Chaves, Fotos, Mail, Mensagens, CloudStorage ou iCloud), não será removido: \(path)"
        case .protectedSecurityCredentials(let path):
            return "Arquivo de segurança protegido (Chaves SSH, GPG, tokens AWS/Cloud ou variáveis de ambiente): \(path)"
        case .outsideCurrentUserHome(let path):
            return "Não é permitido alterar pastas de outros usuários: \(path)"
        case .selfApplicationProtected(let path):
            return "O MeuCleaner não remove a si mesmo: \(path)"
        }
    }
}

public struct SafetyGuard {
    public static let homeDirectoryURL: URL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL

    /// Forbidden system prefixes that can never be modified or trashed (matching CleanerCore.SafetyGuard)
    private static let forbiddenSystemPrefixes: [String] = [
        "/System",
        "/usr",
        "/bin",
        "/sbin",
        "/etc",
        "/private/etc",
        "/private/var/db",
        "/Library/Apple",
        "/Library/CoreServices",
        "/Library/Keychains",
        "/Library/Extensions",
        "/Users/Shared"
    ]

    /// Protected user data folders that the guard refuses to touch even if requested
    public static var protectedUserPaths: [String] {
        let home = homeDirectoryURL.path
        return [
            "\(home)/Documents",
            "\(home)/Desktop",
            "\(home)/Library/Keychains",
            "\(home)/Library/Mail",
            "\(home)/Library/Messages",
            "\(home)/Library/Mobile Documents", // iCloud Drive
            "\(home)/Library/CloudStorage",     // FileProvider Cloud mounts (Google Drive, Dropbox, OneDrive)
            "\(home)/Pictures/Photos Library.photoslibrary",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/.aws",
            "\(home)/.azure",
            "\(home)/.config/gcloud",
            "\(home)/.kube",
            "\(home)/.password-store"
        ]
    }

    /// Protected Apple caches that must never be offered in System Junk (matching CleanerCore.JunkRule.protectedCaches)
    public static let protectedCacheIdentifiers: Set<String> = [
        "com.apple.homekit",
        "com.apple.ap.adprivacyd",
        "com.apple.containermanagerd",
        "com.apple.nsurlsessiond",
        "com.apple.bird",
        "com.apple.akd",
        "cloudkit"
    ]

    /// Sensitive file names that should never be deleted by automated cleaner tasks
    public static let protectedFileNames: Set<String> = [
        ".env",
        ".env.local",
        ".env.production",
        ".env.staging",
        ".env.development",
        "id_rsa",
        "id_rsa.pub",
        "id_ed25519",
        "id_ed25519.pub",
        "id_ecdsa",
        "id_ecdsa.pub",
        "id_dsa",
        "id_dsa.pub",
        "authorized_keys",
        "known_hosts"
    ]

    /// Validates whether a URL is safe to remove or move to the Trash.
    public static func validateCanMoveToTrash(_ url: URL) throws {
        let rawStandardized = url.standardizedFileURL
        let rawPath = rawStandardized.path
        let resolvedPath = rawStandardized.resolvingSymlinksInPath().path

        // Check for sensitive credential and environment files
        let fileName = url.lastPathComponent.lowercased()
        if protectedFileNames.contains(fileName) || fileName.hasPrefix(".env.") {
            throw SafetyViolationError.protectedSecurityCredentials(rawPath)
        }

        let appBundlePath = Bundle.main.bundleURL.standardizedFileURL.path

        // Validate both the raw path and resolved symlink path to prevent symlink traversal attacks
        for path in [rawPath, resolvedPath] {
            // 1. Protect MeuCleaner itself
            if path == appBundlePath || path.lowercased().contains("meucleaner.app") {
                throw SafetyViolationError.selfApplicationProtected(path)
            }

            // 2. Check forbidden system roots
            if path == "/" || path == "/Applications" || path == "/Users" || path == "/Library" {
                throw SafetyViolationError.protectedSystemPath(path)
            }
            for prefix in forbiddenSystemPrefixes {
                if path == prefix || path.hasPrefix(prefix + "/") {
                    throw SafetyViolationError.protectedSystemPath(path)
                }
            }

            // 3. Allow /Applications/<SpecificApp>.app for the Uninstaller, otherwise require user's home folder
            let isThirdPartyAppInApplications = path.hasPrefix("/Applications/") && path.hasSuffix(".app")
            let homePath = homeDirectoryURL.path
            if !isThirdPartyAppInApplications {
                if path == homePath || !path.hasPrefix(homePath + "/") {
                    throw SafetyViolationError.outsideCurrentUserHome(path)
                }
            }

            // 4. Protect critical user directories (Documents, Keychains, Mail, Messages, Photos Library, iCloud, SSH, AWS, etc.)
            for protectedPath in protectedUserPaths {
                if path == protectedPath || path.hasPrefix(protectedPath + "/") {
                    throw SafetyViolationError.protectedUserDataPath(path)
                }
            }
        }
    }

    /// Safely removes an item using the chosen `RemovalMode` after passing `SafetyGuard` validation.
    @discardableResult
    public static func remove(_ url: URL, mode: RemovalMode = .trash) throws -> URL? {
        try validateCanMoveToTrash(url)
        switch mode {
        case .trash:
            var resultingURL: NSURL?
            try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
            return resultingURL as URL?
        case .permanent:
            try FileManager.default.removeItem(at: url)
            return nil
        }
    }

    /// Safely moves an item to the macOS Trash after passing `SafetyGuard` validation.
    @discardableResult
    public static func moveToTrash(_ url: URL) throws -> URL? {
        try remove(url, mode: .trash)
    }

    /// Checks whether the app currently has Full Disk Access by testing read permission on TCC-protected directories.
    public static func hasFullDiskAccess() -> Bool {
        let home = homeDirectoryURL.path
        let protectedProbePaths = [
            "/Library/Application Support/com.apple.TCC/TCC.db",
            "\(home)/Library/Safari",
            "\(home)/Library/Messages",
            "\(home)/Library/Mail"
        ]
        for probe in protectedProbePaths where FileManager.default.fileExists(atPath: probe) {
            if FileManager.default.isReadableFile(atPath: probe) {
                return true
            }
        }
        return false
    }
}
