import SwiftUI

public struct MainView: View {
    @ObservedObject public var scanner: DiskScannerService
    @ObservedObject public var monitor: SystemMonitorService
    @ObservedObject public var updater: SelfUpdaterService
    @Binding public var selectedChannel: CleanerChannel
    public init(scanner: DiskScannerService, monitor: SystemMonitorService, updater: SelfUpdaterService, selectedChannel: Binding<CleanerChannel>) {
        self.scanner = scanner; self.monitor = monitor; self.updater = updater; self._selectedChannel = selectedChannel
    }
    public var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                Label("MeuCleaner", systemImage: "sparkles").font(.title2.bold()).padding(.top, 12)
                ForEach(CleanerChannel.primary) { channel in
                    navigationButton(channel)
                }
                Divider()
                Text("EXPLORAR").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    ForEach(CleanerChannel.explorers) { channel in navigationButton(channel) }
                }
                Spacer()
                Menu {
                    ForEach(CleanerChannel.otherTools) { channel in
                        Button(channel.title, systemImage: channel.symbol) { selectedChannel = channel }
                    }
                } label: { Label("Ferramentas adicionais", systemImage: "ellipsis.circle") }
                Divider()
                Text("\(ByteFormatter.string(from: monitor.diskFreeBytes)) disponíveis").font(.caption).foregroundStyle(.secondary)
                SettingsLink { Label("Ajustes", systemImage: "gearshape") }.buttonStyle(.plain)
            }.padding(16)
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 270)
        } detail: {
            VStack(spacing: 0) {
                if let update = updater.availableUpdate {
                    HStack {
                        Text("Atualização \(update.version) disponível").font(.callout)
                        Spacer()
                        Button(updater.isDownloading ? "Baixando…" : "Atualizar") { Task { await updater.downloadAndInstallUpdate() } }
                            .disabled(updater.isDownloading || updater.isInstalling)
                    }.padding(12).background(Color.blue.opacity(0.08))
                }
                if !CleanerChannel.primary.contains(selectedChannel) && !CleanerChannel.explorers.contains(selectedChannel) {
                    HStack {
                        Button("Voltar à revisão", systemImage: "chevron.left") { selectedChannel = .developerStorage }
                        Spacer()
                    }.padding(.horizontal, 24).padding(.top, 12)
                }
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                if let status = scanner.lastStatusMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text(status).font(.caption).textSelection(.enabled)
                        Spacer()
                        Button("Fechar aviso", systemImage: "xmark") { scanner.lastStatusMessage = nil }.labelStyle(.iconOnly)
                    }.padding(12).background(.regularMaterial)
                }
            }
        }
        .sheet(item: $scanner.cleanupRequest) { CleanupReviewSheet(scanner: scanner, request: $0) }
        .task { if updater.autoCheckOnLaunch { await updater.checkForUpdates(silent: true) } }
    }
    private func navigationButton(_ channel: CleanerChannel) -> some View {
        Button { selectedChannel = channel } label: {
            HStack(spacing: 10) {
                Image(systemName: channel.symbol).foregroundStyle(channel.accentColor).frame(width: 20)
                Text(channel.title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
            }.padding(11)
                .background(selectedChannel == channel ? channel.accentColor.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
        .accessibilityAddTraits(selectedChannel == channel ? .isSelected : [])
    }
    @ViewBuilder private var detail: some View {
        switch selectedChannel {
        case .home: HomeChannelView(scanner: scanner, monitor: monitor, selectedChannel: $selectedChannel)
        case .systemJunk, .developerStorage: DeveloperStorageChannelView(scanner: scanner, reviewCaches: { selectedChannel = .developerStorage })
        case .history: CleanupHistoryView(scanner: scanner, selectedChannel: $selectedChannel)
        case .spaceLens: SpaceLensChannelView(scanner: scanner)
        case .largeAndOld: LargeAndOldChannelView(scanner: scanner)
        case .uninstaller: UninstallerChannelView(scanner: scanner)
        case .leftovers: LeftoversChannelView(scanner: scanner)
        case .trash: TrashChannelView(scanner: scanner)
        case .appUpdater: AppUpdaterChannelView(scanner: scanner)
        case .devAndAI: DevAndAIChannelView(scanner: scanner)
        case .startupItems: StartupItemsChannelView(scanner: scanner)
        case .duplicates: DuplicatesChannelView(scanner: scanner)
        }
    }
}
