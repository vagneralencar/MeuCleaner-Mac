import SwiftUI

public struct StartupItemsChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var selectedScope: StartupAgentScope? = nil

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    private var filteredAgents: [StartupAgentItem] {
        guard let scope = selectedScope else { return scanner.startupAgents }
        return scanner.startupAgents.filter { $0.scope == scope }
    }

    private var activeCount: Int {
        scanner.startupAgents.filter(\.isLoadedInLaunchd).count
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .startupItems,
                trailingBadgeText: "\(activeCount) ativos / \(scanner.startupAgents.count) total",
                actionTitle: scanner.isScanningStartupAgents ? "Lendo..." : "Atualizar Daemons",
                isLoading: scanner.isScanningStartupAgents,
                onAction: {
                    Task { await scanner.scanStartupAgents() }
                }
            )

            // Scope Filter Bar
            HStack(spacing: 8) {
                Button {
                    selectedScope = nil
                } label: {
                    Text("Todos (\(scanner.startupAgents.count))")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedScope == nil ? Color.yellow : Color.primary.opacity(0.07), in: Capsule())
                        .foregroundStyle(selectedScope == nil ? .black : .primary)
                }
                .buttonStyle(.plain)

                ForEach(StartupAgentScope.allCases) { scope in
                    let count = scanner.startupAgents.filter { $0.scope == scope }.count
                    Button {
                        selectedScope = scope
                    } label: {
                        Text("\(scope.shortBadge) (\(count))")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(selectedScope == scope ? Color.yellow : Color.primary.opacity(0.07), in: Capsule())
                            .foregroundStyle(selectedScope == scope ? .black : .primary)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }

            if scanner.isScanningStartupAgents {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("Inspecionando LaunchAgents, LaunchDaemons e estado no launchctl...")
                    Spacer()
                }
                Spacer()
            } else if filteredAgents.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nenhum agente de inicialização nesta categoria",
                    systemImage: "bolt.horizontal.circle",
                    description: Text("Nenhum LaunchAgent ou Daemon de terceiros encontrado.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredAgents) { item in
                            GlassCard(padding: 12, cornerRadius: 12) {
                                HStack(spacing: 14) {
                                    Circle()
                                        .fill(item.isLoadedInLaunchd ? Color.green : Color.secondary.opacity(0.35))
                                        .frame(width: 10, height: 10)
                                        .shadow(color: item.isLoadedInLaunchd ? .green.opacity(0.6) : .clear, radius: 4)

                                    VStack(alignment: .leading, spacing: 3) {
                                        HStack(spacing: 8) {
                                            Text(item.inferredVendorName)
                                                .font(.subheadline.weight(.bold))

                                            Text(item.label)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundStyle(.secondary)

                                            Text(item.scope.shortBadge)
                                                .font(.system(size: 10, weight: .bold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.yellow.opacity(0.18), in: Capsule())
                                                .foregroundStyle(.yellow)

                                            if item.keepAlive {
                                                Text("KeepAlive")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                                    .foregroundStyle(.orange)
                                            }
                                        }

                                        Text("Binário: \(item.programPath)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(item.isLoadedInLaunchd ? "Ativo" : "Pausado")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(item.isLoadedInLaunchd ? .green : .secondary)

                                    Button(item.isLoadedInLaunchd ? "Pausar" : "Ativar") {
                                        Task { await scanner.toggleLaunchAgent(item) }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.plistURL])
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Mostrar .plist no Finder")

                                    if item.scope == .userAgent {
                                        Button(role: .destructive) {
                                            Task { await scanner.removeStartupAgentToTrash(item) }
                                        } label: {
                                            Image(systemName: "trash")
                                                .foregroundStyle(.red)
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help("Descarregar e mover .plist para a Lixeira")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            SafetyNoticePill(text: "Daemons da Apple (com.apple.*) são ocultados automaticamente para proteger a estabilidade do macOS.")
        }
        .padding(24)
        .task {
            if scanner.startupAgents.isEmpty && !scanner.isScanningStartupAgents {
                await scanner.scanStartupAgents()
            }
        }
    }
}
