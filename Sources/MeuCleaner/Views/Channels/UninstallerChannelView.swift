import SwiftUI

public enum AppSortOption: String, CaseIterable, Identifiable {
    case size = "Tamanho"
    case name = "Nome"
    case lastUsed = "Último uso"

    public var id: String { rawValue }
}

public struct UninstallerChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var searchText: String = ""
    @State private var sortOption: AppSortOption = .size
    @State private var selectedAppID: UUID? = nil

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    private var runningBundleIDs: Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    private var filteredApps: [InstalledApp] {
        let base: [InstalledApp]
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            base = scanner.installedApps
        } else {
            let query = searchText.lowercased()
            base = scanner.installedApps.filter {
                $0.name.lowercased().contains(query) || $0.bundleIdentifier.lowercased().contains(query)
            }
        }
        switch sortOption {
        case .size:
            return base.sorted { $0.totalSizeBytes > $1.totalSizeBytes }
        case .name:
            return base.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .lastUsed:
            return base.sorted { ($0.lastUsedDate ?? .distantPast) > ($1.lastUsedDate ?? .distantPast) }
        }
    }

    private var activeApp: InstalledApp? {
        if let id = selectedAppID, let found = scanner.installedApps.first(where: { $0.id == id }) {
            return found
        }
        return filteredApps.first
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .uninstaller,
                trailingBadgeText: "\(scanner.installedApps.count) apps",
                actionTitle: scanner.isScanningApps ? "Carregando..." : "Atualizar Lista",
                isLoading: scanner.isScanningApps,
                onAction: {
                    Task { await scanner.scanAppsAndLeftovers() }
                }
            )

            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar app por nome ou bundle ID...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Picker("Ordenar por:", selection: $sortOption) {
                    ForEach(AppSortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 280)
            }

            if scanner.isScanningApps {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Mapeando aplicativos instalados e restos associados na Library...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else {
                HStack(alignment: .top, spacing: 18) {
                    // Left: Installed Apps List
                    GlassCard(padding: 12, cornerRadius: 16) {
                        ScrollView {
                            LazyVStack(spacing: 6) {
                                ForEach(filteredApps) { app in
                                    let isSelected = activeApp?.id == app.id
                                    let isRunning = runningBundleIDs.contains(app.bundleIdentifier.lowercased())

                                    Button {
                                        selectedAppID = app.id
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                                                .resizable()
                                                .frame(width: 34, height: 34)

                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text(app.name)
                                                        .font(.subheadline.weight(.semibold))
                                                        .lineLimit(1)
                                                    if isRunning {
                                                        Circle()
                                                            .fill(.green)
                                                            .frame(width: 6, height: 6)
                                                            .help("App aberto")
                                                    }
                                                }
                                                Text("v\(app.version) · \(app.relatedFiles.count) itens na Library")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }

                                            Spacer()

                                            Text(ByteFormatter.string(from: app.totalSizeBytes))
                                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                                .foregroundStyle(isSelected ? .red : .primary)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(isSelected ? Color.red.opacity(0.15) : Color.clear)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(width: 330)

                    // Right: Selected App Detail & Associated Library Files
                    GlassCard(padding: 18, cornerRadius: 16) {
                        if let app = activeApp {
                            let blocker = app.uninstallBlocker(runningBundleIDs: runningBundleIDs)

                            VStack(alignment: .leading, spacing: 14) {
                                HStack(spacing: 16) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.bundleURL.path))
                                        .resizable()
                                        .frame(width: 56, height: 56)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(app.name)
                                                .font(.title2.bold())
                                            if app.hasAppStoreReceipt {
                                                Text("App Store")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.blue.opacity(0.15), in: Capsule())
                                                    .foregroundStyle(.blue)
                                            }
                                        }
                                        Text("\(app.bundleIdentifier) · Versão \(app.version)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        HStack(spacing: 12) {
                                            Label("App: \(ByteFormatter.string(from: app.appSizeBytes))", systemImage: "app.fill")
                                                .font(.caption.weight(.medium))
                                            Label("Restos na Library: \(ByteFormatter.string(from: app.leftoversSizeBytes))", systemImage: "folder.fill.badge.gearshape")
                                                .font(.caption.weight(.medium))
                                                .foregroundStyle(.red)
                                        }
                                    }

                                    Spacer()

                                    if let blocker {
                                        VStack(alignment: .trailing, spacing: 6) {
                                            Text(blocker.badgeText)
                                                .font(.caption.weight(.bold))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 5)
                                                .background(Color.orange.opacity(0.18), in: Capsule())
                                                .foregroundStyle(.orange)

                                            if blocker == .runningApp {
                                                Button("Encerrar \(app.name)") {
                                                    if let running = NSWorkspace.shared.runningApplications.first(where: {
                                                        $0.bundleIdentifier?.lowercased() == app.bundleIdentifier.lowercased()
                                                    }) {
                                                        running.terminate()
                                                    }
                                                }
                                                .buttonStyle(.borderedProminent)
                                                .tint(.orange)
                                                .controlSize(.small)
                                            }
                                        }
                                    } else {
                                        Button {
                                            Task {
                                                _ = await scanner.uninstallApp(app)
                                            }
                                        } label: {
                                            Label("Desinstalar (\(ByteFormatter.string(from: app.totalSizeBytes)))", systemImage: "trash.fill")
                                                .fontWeight(.semibold)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.red)
                                    }
                                }

                                Divider()

                                Text("Cada app com tudo o que ele espalhou pelo Mac. Você vê tudo antes de remover qualquer coisa:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                ScrollView {
                                    VStack(alignment: .leading, spacing: 8) {
                                        // Main App Bundle row
                                        HStack(spacing: 10) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.red)
                                            Text("App")
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 2)
                                                .background(Color.red.opacity(0.14), in: Capsule())
                                                .foregroundStyle(.red)
                                            Text(app.bundleURL.path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            Spacer()
                                            Text(ByteFormatter.string(from: app.appSizeBytes))
                                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                        }
                                        .padding(10)
                                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))

                                        if app.relatedFiles.isEmpty {
                                            Text("Nenhum arquivo extra encontrado em ~/Library para este app.")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.top, 8)
                                        } else {
                                            ForEach(app.relatedFiles) { related in
                                                HStack(spacing: 10) {
                                                    Image(systemName: "folder.badge.gearshape")
                                                        .foregroundStyle(.orange)
                                                    Text(related.kind.rawValue)
                                                        .font(.system(size: 10, weight: .bold))
                                                        .padding(.horizontal, 7)
                                                        .padding(.vertical, 2)
                                                        .background(Color.orange.opacity(0.15), in: Capsule())
                                                        .foregroundStyle(.orange)

                                                    if let caution = related.caution {
                                                        Text(caution.rawValue)
                                                            .font(.system(size: 10, weight: .bold))
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.yellow.opacity(0.2), in: Capsule())
                                                            .foregroundStyle(.yellow)
                                                    }

                                                    Text(related.url.path)
                                                        .font(.caption)
                                                        .foregroundStyle(.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                    Spacer()
                                                    Text(ByteFormatter.string(from: related.sizeBytes))
                                                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                                                    Button {
                                                        NSWorkspace.shared.activateFileViewerSelecting([related.url])
                                                    } label: {
                                                        Image(systemName: "magnifyingglass")
                                                            .font(.caption2)
                                                    }
                                                    .buttonStyle(.borderless)
                                                }
                                                .padding(10)
                                                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
                                            }
                                        }
                                    }
                                }
                            }
                        } else {
                            Spacer()
                            ContentUnavailableView(
                                "Escolha um app",
                                systemImage: "square.stack.3d.up.slash",
                                description: Text("Você vê o app e tudo o que ele espalhou pelo Mac antes de remover qualquer coisa.")
                            )
                            Spacer()
                        }
                    }
                }
            }

            SafetyNoticePill(text: "Apps abertos pedem para encerrar primeiro. Desinstalar envia o app e seus arquivos marcados para a Lixeira.")
        }
        .padding(24)
        .task {
            if scanner.installedApps.isEmpty && !scanner.isScanningApps {
                await scanner.scanAppsAndLeftovers()
            }
        }
    }
}
