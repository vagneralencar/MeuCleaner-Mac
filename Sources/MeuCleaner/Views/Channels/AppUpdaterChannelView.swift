import SwiftUI

public struct AppUpdaterChannelView: View {
    @ObservedObject public var scanner: DiskScannerService

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    private var activeUpdatesCount: Int {
        scanner.updatableApps.filter { !$0.isSkipped }.count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .appUpdater,
                trailingBadgeText: "\(activeUpdatesCount) disponíveis",
                actionTitle: scanner.isScanningUpdates ? "Verificando..." : "Buscar Atualizações",
                isLoading: scanner.isScanningUpdates,
                onAction: {
                    Task { await scanner.scanForAppUpdates() }
                }
            )

            if activeUpdatesCount > 0 {
                GlassCard(padding: 14, cornerRadius: 14) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.green)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(activeUpdatesCount) atualizações prontas para instalar")
                                .font(.subheadline.weight(.bold))
                            Text("Instala pacotes via Homebrew Cask automaticamente e abre atualizadores Sparkle/App Store.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            Task { await scanner.installAllAppUpdates() }
                        } label: {
                            Label("Atualizar Tudo (\(activeUpdatesCount))", systemImage: "bolt.fill")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(!scanner.updatingAppIDs.isEmpty)
                    }
                }
            }

            if scanner.isScanningUpdates {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Consultando Homebrew Casks, Mac App Store Lookup API e feeds Sparkle...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if scanner.updatableApps.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Tudo em dia!",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Nenhum aplicativo tem versão mais nova pendente no Homebrew, Sparkle ou App Store.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(scanner.updatableApps) { item in
                            let isUpdating = scanner.updatingAppIDs.contains(item.id)

                            GlassCard(padding: 14, cornerRadius: 14) {
                                HStack(alignment: .top, spacing: 14) {
                                    if let bundleURL = item.bundleURL {
                                        Image(nsImage: NSWorkspace.shared.icon(forFile: bundleURL.path))
                                            .resizable()
                                            .frame(width: 40, height: 40)
                                    } else {
                                        Image(systemName: "shippingbox.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(.green)
                                            .frame(width: 40, height: 40)
                                            .background(Color.green.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(item.name)
                                                .font(.headline)
                                                .strikethrough(item.isSkipped)

                                            Text(item.source.rawValue)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Color.green.opacity(0.15), in: Capsule())
                                                .foregroundStyle(.green)

                                            Text("\(item.currentVersion) → \(item.latestVersion)")
                                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(item.releaseNotes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    HStack(spacing: 8) {
                                        Button(item.isSkipped ? "Reativar" : "Ignorar versão") {
                                            scanner.toggleSkipUpdate(for: item.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        Button {
                                            Task { await scanner.installAppUpdate(item) }
                                        } label: {
                                            HStack(spacing: 6) {
                                                if isUpdating {
                                                    ProgressView()
                                                        .controlSize(.small)
                                                } else {
                                                    Image(systemName: "arrow.down.circle.fill")
                                                }
                                                Text(isUpdating ? "Atualizando..." : "Atualizar")
                                            }
                                        }
                                        .buttonStyle(.borderedProminent)
                                        .tint(.green)
                                        .controlSize(.small)
                                        .disabled(isUpdating || item.isSkipped)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            SafetyNoticePill(text: "Fontes suportadas em tempo real: Homebrew Cask (brew upgrade), feeds XML Sparkle (SUFeedURL) e Mac App Store Lookup API.")
        }
        .padding(24)
        .task {
            if scanner.updatableApps.isEmpty && !scanner.isScanningUpdates {
                await scanner.scanForAppUpdates()
            }
        }
    }
}
