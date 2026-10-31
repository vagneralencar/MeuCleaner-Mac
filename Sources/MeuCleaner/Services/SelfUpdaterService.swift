import Foundation
import AppKit
import Combine

public struct AppUpdateInfo: Identifiable, Sendable {
    public var id: String { tagName }
    public let tagName: String
    public let version: String
    public let title: String
    public let releaseNotes: String
    public let htmlURL: URL
    public let publishedAt: Date?
    public let downloadURL: URL?
    public let assetName: String?
    public let assetSizeBytes: Int64

    public init(
        tagName: String,
        version: String,
        title: String,
        releaseNotes: String,
        htmlURL: URL,
        publishedAt: Date?,
        downloadURL: URL?,
        assetName: String?,
        assetSizeBytes: Int64
    ) {
        self.tagName = tagName
        self.version = version
        self.title = title
        self.releaseNotes = releaseNotes
        self.htmlURL = htmlURL
        self.publishedAt = publishedAt
        self.downloadURL = downloadURL
        self.assetName = assetName
        self.assetSizeBytes = assetSizeBytes
    }
}

@MainActor
public final class SelfUpdaterService: NSObject, ObservableObject, URLSessionDownloadDelegate {
    @Published public var isChecking: Bool = false
    @Published public var isDownloading: Bool = false
    @Published public var isInstalling: Bool = false
    @Published public var downloadProgress: Double = 0.0
    @Published public var availableUpdate: AppUpdateInfo?
    @Published public var lastCheckDate: Date?
    @Published public var statusMessage: String?
    @Published public var autoCheckOnLaunch: Bool {
        didSet {
            UserDefaults.standard.set(autoCheckOnLaunch, forKey: Self.autoCheckKey)
        }
    }

    public static let repositoryOwner = "vagneralencar"
    public static let repositoryName = "MeuCleaner-Mac"
    private static let autoCheckKey = "MeuCleaner.AutoCheckUpdatesOnLaunch"
    private static let lastCheckKey = "MeuCleaner.LastUpdateCheckDate"

    public var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.2.0"
    }

    public var currentBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "3"
    }

    private var downloadTask: URLSessionDownloadTask?
    private var downloadContinuation: CheckedContinuation<URL, Error>?

    public override init() {
        if UserDefaults.standard.object(forKey: Self.autoCheckKey) == nil {
            self.autoCheckOnLaunch = true
        } else {
            self.autoCheckOnLaunch = UserDefaults.standard.bool(forKey: Self.autoCheckKey)
        }
        if let storedDate = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date {
            self.lastCheckDate = storedDate
        }
        super.init()
    }

    // MARK: - Check For Updates via GitHub Releases API

    public func checkForUpdates(silent: Bool = false) async {
        guard !isChecking else { return }
        isChecking = true
        if !silent {
            statusMessage = "Verificando se há atualizações do MeuCleaner..."
        }

        defer {
            isChecking = false
            lastCheckDate = Date()
            UserDefaults.standard.set(lastCheckDate, forKey: Self.lastCheckKey)
        }

        let apiURLString = "https://api.github.com/repos/\(Self.repositoryOwner)/\(Self.repositoryName)/releases/latest"
        guard let apiURL = URL(string: apiURLString) else {
            if !silent { statusMessage = "URL de verificação inválida." }
            return
        }

        var request = URLRequest(url: apiURL)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.setValue("MeuCleaner-App/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if !silent {
                    statusMessage = "Não foi possível verificar atualizações no momento (status: \((response as? HTTPURLResponse)?.statusCode ?? 0))."
                }
                return
            }

            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if !silent { statusMessage = "Resposta de atualização ilegível." }
                return
            }

            let releaseTitle = (json["name"] as? String) ?? tagName
            let releaseNotes = (json["body"] as? String) ?? ""
            let htmlURLStr = (json["html_url"] as? String) ?? "https://github.com/\(Self.repositoryOwner)/\(Self.repositoryName)/releases"
            let htmlURL = URL(string: htmlURLStr) ?? apiURL

            let isoDateFormatter = ISO8601DateFormatter()
            let publishedAt = (json["published_at"] as? String).flatMap { isoDateFormatter.date(from: $0) }

            // Locate .dmg or .zip asset
            var downloadURL: URL?
            var assetName: String?
            var assetSizeBytes: Int64 = 0

            if let assets = json["assets"] as? [[String: Any]] {
                // Priority 1: .dmg package, Priority 2: .zip package
                let candidateAsset = assets.first(where: {
                    let name = ($0["name"] as? String)?.lowercased() ?? ""
                    return name.hasSuffix(".dmg")
                }) ?? assets.first(where: {
                    let name = ($0["name"] as? String)?.lowercased() ?? ""
                    return name.hasSuffix(".zip")
                })

                if let chosen = candidateAsset {
                    assetName = chosen["name"] as? String
                    if let size = chosen["size"] as? Int64 {
                        assetSizeBytes = size
                    } else if let sizeInt = chosen["size"] as? Int {
                        assetSizeBytes = Int64(sizeInt)
                    }
                    if let urlString = chosen["browser_download_url"] as? String {
                        downloadURL = URL(string: urlString)
                    }
                }
            }

            let normalizedRemoteVersion = AppVersion.normalize(tagName)
            let isNewer = AppVersion.isNewer(normalizedRemoteVersion, than: currentVersion)

            if isNewer {
                availableUpdate = AppUpdateInfo(
                    tagName: tagName,
                    version: normalizedRemoteVersion,
                    title: releaseTitle,
                    releaseNotes: releaseNotes,
                    htmlURL: htmlURL,
                    publishedAt: publishedAt,
                    downloadURL: downloadURL,
                    assetName: assetName,
                    assetSizeBytes: assetSizeBytes
                )
                statusMessage = "Nova versão \(normalizedRemoteVersion) disponível!"
            } else {
                availableUpdate = nil
                if !silent {
                    statusMessage = "O MeuCleaner v\(currentVersion) está atualizado!"
                }
            }
        } catch {
            if !silent {
                statusMessage = "Falha ao conectar com o servidor: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Download and Atomic Swap Install

    public func downloadAndInstallUpdate() async {
        guard let update = availableUpdate, let downloadURL = update.downloadURL else {
            statusMessage = "Pacote de atualização não encontrado."
            return
        }

        isDownloading = true
        downloadProgress = 0.0
        statusMessage = "Baixando \(update.assetName ?? "atualização")..."

        do {
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            let tempDownloadedURL: URL = try await withCheckedThrowingContinuation { continuation in
                self.downloadContinuation = continuation
                let task = session.downloadTask(with: downloadURL)
                self.downloadTask = task
                task.resume()
            }

            isDownloading = false
            isInstalling = true
            statusMessage = "Instalando nova versão..."

            try await performAppInstallation(from: tempDownloadedURL, assetName: update.assetName ?? "update")
            statusMessage = "Atualização concluída! Reiniciando..."
        } catch {
            isDownloading = false
            isInstalling = false
            statusMessage = "Erro ao atualizar: \(error.localizedDescription)"
            // Fallback to opening release page
            NSWorkspace.shared.open(update.htmlURL)
        }
    }

    private func performAppInstallation(from fileURL: URL, assetName: String) async throws {
        let isDMG = assetName.lowercased().hasSuffix(".dmg")
        let isZip = assetName.lowercased().hasSuffix(".zip")

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        var extractedAppURL: URL?

        if isDMG {
            // Mount DMG silently and locate .app
            let mountPoint = tempDir.appendingPathComponent("mount", isDirectory: true)
            try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)

            let attachProc = Process()
            attachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            attachProc.arguments = ["attach", fileURL.path, "-mountpoint", mountPoint.path, "-nobrowse", "-readonly", "-quiet"]
            try attachProc.run()
            attachProc.waitUntilExit()

            let contents = try? fm.contentsOfDirectory(at: mountPoint, includingPropertiesForKeys: nil)
            if let appInDMG = contents?.first(where: { $0.pathExtension == "app" }) {
                let copiedApp = tempDir.appendingPathComponent("MeuCleaner.app")
                try? fm.copyItem(at: appInDMG, to: copiedApp)
                extractedAppURL = copiedApp
            }

            // Unmount DMG
            let detachProc = Process()
            detachProc.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            detachProc.arguments = ["detach", mountPoint.path, "-quiet", "-force"]
            try? detachProc.run()
            detachProc.waitUntilExit()
        } else if isZip {
            // Unzip via ditto
            let dittoProc = Process()
            dittoProc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            dittoProc.arguments = ["-x", "-k", fileURL.path, tempDir.path]
            try dittoProc.run()
            dittoProc.waitUntilExit()

            let contents = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
            extractedAppURL = contents?.first(where: { $0.pathExtension == "app" })
        }

        guard let sourceApp = extractedAppURL, fm.fileExists(atPath: sourceApp.path) else {
            // Fallback: If bundle extraction failed, open the downloaded file directly
            NSWorkspace.shared.open(fileURL)
            return
        }

        // Target application location
        let targetAppPath = Bundle.main.bundleURL.path.contains(".app")
            ? Bundle.main.bundleURL.path
            : "/Applications/MeuCleaner.app"

        // Write an atomic relaunch bash helper script that waits for exit, swaps bundle, and relaunches
        let scriptContent = """
        #!/bin/bash
        sleep 1
        kill -9 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null || true
        rm -rf "\(targetAppPath)"
        cp -R "\(sourceApp.path)" "\(targetAppPath)"
        xattr -cr "\(targetAppPath)" 2>/dev/null || true
        open "\(targetAppPath)"
        rm -rf "\(tempDir.path)"
        """

        let scriptURL = tempDir.appendingPathComponent("relaunch.sh")
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Launch detached process and exit app cleanly
        let runner = Process()
        runner.executableURL = URL(fileURLWithPath: "/bin/bash")
        runner.arguments = [scriptURL.path]
        try runner.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }

    // MARK: - URLSessionDownloadDelegate

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress: Double
        if totalBytesExpectedToWrite > 0 {
            progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        } else {
            progress = 0.5
        }
        Task { @MainActor in
            self.downloadProgress = min(1.0, max(0.0, progress))
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // Move to permanent temporary file so it isn't deleted when delegate exits
        let fm = FileManager.default
        let tempTarget = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + "-" + (downloadTask.response?.suggestedFilename ?? "update.dmg"))
        do {
            try? fm.removeItem(at: tempTarget)
            try fm.moveItem(at: location, to: tempTarget)
            Task { @MainActor in
                self.downloadContinuation?.resume(returning: tempTarget)
                self.downloadContinuation = nil
            }
        } catch {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }

    public nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.downloadContinuation?.resume(throwing: error)
                self.downloadContinuation = nil
            }
        }
    }
}
