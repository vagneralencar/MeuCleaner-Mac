import SwiftUI

public struct HomeChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @ObservedObject public var monitor: SystemMonitorService
    @Binding public var selectedChannel: CleanerChannel

    public init(
        scanner: DiskScannerService,
        monitor: SystemMonitorService,
        selectedChannel: Binding<CleanerChannel>
    ) {
        self.scanner = scanner
        self.monitor = monitor
        self._selectedChannel = selectedChannel
    }

    private var isScanningAny: Bool {
        scanner.isScanningJunk || scanner.isScanningLeftovers || scanner.isScanningTrash
    }

    private var totalReclaimableBytes: Int64 {
        scanner.selectedJunkBytes + scanner.totalLeftoversBytes + scanner.totalTrashBytes
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ChannelHeaderView(
                    channel: .home,
                    trailingBadgeText: ByteFormatter.string(from: totalReclaimableBytes),
                    actionTitle: isScanningAny ? "Escaneando..." : "Escanear Mac",
                    isLoading: isScanningAny,
                    onAction: {
                        Task {
                            await scanner.runSmartScan()
                        }
                    }
                )

                // Vigia da Lixeira Live Banner on Home
                ForEach(scanner.trashedAppAlerts) { alert in
                    GlassCard(padding: 14, cornerRadius: 14) {
                        HStack(spacing: 12) {
                            Image(systemName: "bell.badge.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vigia da Lixeira: \(alert.appName) deixou \(ByteFormatter.string(from: alert.totalLeftoversBytes)) na Library")
                                    .font(.subheadline.weight(.bold))
                                Text("Você apagou o app no Finder, mas ainda restam \(alert.leftoverFiles.count) pastas órfãs.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Limpar Restos Agora") {
                                Task { await scanner.cleanTrashedAppLeftovers(alert) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                            .controlSize(.small)
                        }
                    }
                }

                // Hero Smart Summary Card
                GlassCard(padding: 20, cornerRadius: 18) {
                    HStack(spacing: 24) {
                        ZStack {
                            Circle()
                                .stroke(Color.blue.opacity(0.15), lineWidth: 14)
                                .frame(width: 118, height: 118)

                            Circle()
                                .trim(from: 0, to: CGFloat(monitor.diskUsedPercent / 100.0))
                                .stroke(
                                    AngularGradient(
                                        colors: [.blue, .cyan, .indigo, .blue],
                                        center: .center
                                    ),
                                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))
                                .frame(width: 118, height: 118)

                            VStack(spacing: 2) {
                                Text("\(Int(100 - monitor.diskUsedPercent))%")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                Text("LIVRE")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 10) {
                                Text("Diagnóstico Inteligente do Mac")
                                    .font(.title3.bold())
                                if let duration = scanner.lastScanDurationSeconds {
                                    Text(String(format: "lido em %.1fs", duration))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.14), in: Capsule())
                                        .foregroundStyle(.blue)
                                }
                                if scanner.totalLifetimeFreedBytes > 0 {
                                    Text("Já liberado: \(ByteFormatter.string(from: scanner.totalLifetimeFreedBytes))")
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.green.opacity(0.16), in: Capsule())
                                        .foregroundStyle(.green)
                                }
                            }

                            Text("Escanear só lê: nada sai do lugar até você clicar em Limpar. Todo arquivo removido vai para a Lixeira do macOS antes.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 18) {
                                Label(
                                    "Livre: \(ByteFormatter.string(from: monitor.diskFreeBytes))",
                                    systemImage: "internaldrive.fill"
                                )
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.blue)

                                Label(
                                    "Total: \(ByteFormatter.string(from: monitor.diskTotalBytes))",
                                    systemImage: "square.stack.3d.up.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Label(
                                    "RAM: \(ByteFormatter.string(from: monitor.memoryUsedBytes)) / \(ByteFormatter.string(from: monitor.memoryTotalBytes))",
                                    systemImage: "memorychip"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.top, 2)
                        }

                        Spacer()

                        if scanner.selectedJunkBytes > 0 {
                            VStack(alignment: .trailing, spacing: 8) {
                                Button {
                                    Task {
                                        _ = await scanner.cleanSelectedJunk()
                                    }
                                } label: {
                                    Label("Limpar \(ByteFormatter.string(from: scanner.selectedJunkBytes))", systemImage: "sparkles")
                                        .fontWeight(.semibold)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)

                                Text("Envia caches e logs para a Lixeira")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // Three Smart Pillars: System Junk, Leftovers, Trash
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    SmartPillarCard(
                        code: "01",
                        title: "Lixo do Sistema",
                        subtitle: "\(scanner.junkItems.count) locais encontrados",
                        amountText: ByteFormatter.string(from: scanner.totalJunkBytes),
                        symbol: "internaldrive.trianglebadge.exclamationmark",
                        color: .orange,
                        buttonLabel: "Revisar Lixo"
                    ) {
                        selectedChannel = .systemJunk
                    }

                    SmartPillarCard(
                        code: "05",
                        title: "Restos de Apps",
                        subtitle: "\(scanner.leftoverGroups.count) apps órfãos na Library",
                        amountText: ByteFormatter.string(from: scanner.totalLeftoversBytes),
                        symbol: "puzzlepiece.extension.fill",
                        color: .indigo,
                        buttonLabel: "Revisar Restos"
                    ) {
                        selectedChannel = .leftovers
                    }

                    SmartPillarCard(
                        code: "06",
                        title: "Na Lixeira",
                        subtitle: "\(scanner.trashItems.count) itens aguardando",
                        amountText: ByteFormatter.string(from: scanner.totalTrashBytes),
                        symbol: "trash.fill",
                        color: .pink,
                        buttonLabel: "Abrir Lixeira"
                    ) {
                        selectedChannel = .trash
                    }
                }

                // Quick Navigation Grid for remaining channels
                Text("Ferramentas de Profundidade")
                    .font(.headline)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    QuickChannelRowCard(
                        channel: .spaceLens,
                        badge: "Mapa em Anéis"
                    ) {
                        selectedChannel = .spaceLens
                    }

                    QuickChannelRowCard(
                        channel: .largeAndOld,
                        badge: "\(scanner.largeFiles.count) arquivos"
                    ) {
                        selectedChannel = .largeAndOld
                    }

                    QuickChannelRowCard(
                        channel: .uninstaller,
                        badge: "\(scanner.installedApps.count) apps instalados"
                    ) {
                        selectedChannel = .uninstaller
                    }

                    QuickChannelRowCard(
                        channel: .appUpdater,
                        badge: "Homebrew, Sparkle & MAS"
                    ) {
                        selectedChannel = .appUpdater
                    }

                    QuickChannelRowCard(
                        channel: .devAndAI,
                        badge: "PRO · node_modules & IA"
                    ) {
                        selectedChannel = .devAndAI
                    }

                    QuickChannelRowCard(
                        channel: .startupItems,
                        badge: "PRO · LaunchAgents"
                    ) {
                        selectedChannel = .startupItems
                    }

                    QuickChannelRowCard(
                        channel: .duplicates,
                        badge: "PRO · SHA-256"
                    ) {
                        selectedChannel = .duplicates
                    }
                }

                // Full Disk Access & Safety Guard Banner
                GlassCard(material: .ultraThinMaterial, padding: 14, cornerRadius: 14) {
                    HStack(spacing: 14) {
                        Image(systemName: scanner.hasFullDiskAccess ? "lock.open.shield.fill" : "shield.lefthalf.filled.badge.checkmark")
                            .font(.system(size: 24))
                            .foregroundStyle(scanner.hasFullDiskAccess ? .green : .blue)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(scanner.hasFullDiskAccess ? "Acesso Total ao Disco Ativo" : "Acesso Total ao Disco (Opcional) + Guarda de Segurança")
                                .font(.subheadline.weight(.semibold))
                            Text("A Guarda de Segurança recusa mexer em pastas do sistema, Documentos, Chaves, Mail, Mensagens, biblioteca do Fotos e iCloud Drive.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if !scanner.hasFullDiskAccess {
                            Button("Abrir Ajustes de Privacidade") {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(24)
        }
    }
}

private struct SmartPillarCard: View {
    let code: String
    let title: String
    let subtitle: String
    let amountText: String
    let symbol: String
    let color: Color
    let buttonLabel: String
    let action: () -> Void

    var body: some View {
        GlassCard(padding: 16, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 38, height: 38)
                        .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Spacer()

                    Text("CH \(code)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(amountText)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Button(action: action) {
                    HStack {
                        Text(buttonLabel)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.bold())
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .tint(color)
            }
        }
    }
}

private struct QuickChannelRowCard: View {
    let channel: CleanerChannel
    let badge: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassCard(padding: 14, cornerRadius: 14) {
                HStack(spacing: 12) {
                    Image(systemName: channel.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(channel.accentColor)
                        .frame(width: 36, height: 36)
                        .background(channel.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(channel.code)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(channel.accentColor)
                            Text(channel.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                        }
                        Text(channel.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(badge)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(channel.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(channel.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
