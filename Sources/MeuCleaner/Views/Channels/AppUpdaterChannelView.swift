import SwiftUI

public struct AppUpdaterChannelView: View {
    @ObservedObject public var scanner: DiskScannerService

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .appUpdater,
                trailingBadgeText: "\(scanner.updatableApps.count) verificados",
                actionTitle: scanner.isScanningUpdates ? "Verificando..." : "Buscar Atualizações",
                isLoading: scanner.isScanningUpdates,
                onAction: {
                    Task { await scanner.scanForAppUpdates() }
                }
            )

            if scanner.isScanningUpdates {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Consultando Homebrew Casks e feeds Sparkle dos seus aplicativos...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if scanner.updatableApps.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Seus apps estão em dia",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Clique em Buscar Atualizações para consultar o Homebrew e feeds Sparkle dos apps instalados.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(scanner.updatableApps) { item in
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
                                        Button(item.isSkipped ? "Reativar" : "Pular versão") {
                                            scanner.toggleSkipUpdate(for: item.id)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)

                                        if let bundleURL = item.bundleURL {
                                            Button("Abrir App") {
                                                NSWorkspace.shared.openApplication(
                                                    at: bundleURL,
                                                    configuration: NSWorkspace.OpenConfiguration()
                                                )
                                            }
                                            .buttonStyle(.borderedProminent)
                                            .tint(.green)
                                            .controlSize(.small)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            SafetyNoticePill(text: "Fontes suportadas: feeds Sparkle (SUFeedURL) e pacotes Homebrew Cask instalados localmente.")
        }
        .padding(24)
        .task {
            if scanner.updatableApps.isEmpty && !scanner.isScanningUpdates {
                if scanner.installedApps.isEmpty {
                    await scanner.scanAppsAndLeftovers()
                }
                await scanner.scanForAppUpdates()
            }
        }
    }
}
