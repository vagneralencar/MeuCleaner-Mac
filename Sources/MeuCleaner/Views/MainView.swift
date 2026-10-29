import SwiftUI

public struct MainView: View {
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

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // App Brand Header in Sidebar
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [.blue, .cyan],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 34, height: 34)
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("MeuCleaner")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                        Text("macOS Native Cleaner")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 10)

                // Channels 00–07 List
                List(CleanerChannel.allCases, selection: $selectedChannel) { channel in
                    HStack(spacing: 10) {
                        Image(systemName: channel.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(selectedChannel == channel ? .white : channel.accentColor)
                            .frame(width: 24, height: 24)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selectedChannel == channel ? channel.accentColor : channel.accentColor.opacity(0.14))
                            )

                        VStack(alignment: .leading, spacing: 1) {
                            Text(channel.title)
                                .font(.system(size: 13, weight: .medium))
                        }

                        Spacer()

                        Text(channel.code)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                    .tag(channel)
                }
                .listStyle(.sidebar)

                Divider()

                // Live Storage & System Footer in Sidebar
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Macintosh HD", systemImage: "internaldrive.fill")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(ByteFormatter.string(from: monitor.diskFreeBytes)) livres")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(.blue)
                    }

                    ProgressView(value: monitor.diskUsedPercent, total: 100.0)
                        .tint(.blue)
                        .controlSize(.small)

                    HStack {
                        Text("CPU \(Int(monitor.cpuUsagePercent))%")
                        Spacer()
                        Text("RAM \(Int(monitor.memoryPressurePercent))%")
                        Spacer()
                        Text("⌘0–⌘7")
                    }
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(.ultraThinMaterial)
            }
            .navigationSplitViewColumnWidth(min: 225, ideal: 240, max: 270)
        } detail: {
            ZStack(alignment: .bottom) {
                Group {
                    switch selectedChannel {
                    case .home:
                        HomeChannelView(
                            scanner: scanner,
                            monitor: monitor,
                            selectedChannel: $selectedChannel
                        )
                    case .systemJunk:
                        SystemJunkChannelView(scanner: scanner)
                    case .spaceLens:
                        SpaceLensChannelView(scanner: scanner)
                    case .largeAndOld:
                        LargeAndOldChannelView(scanner: scanner)
                    case .uninstaller:
                        UninstallerChannelView(scanner: scanner)
                    case .leftovers:
                        LeftoversChannelView(scanner: scanner)
                    case .trash:
                        TrashChannelView(scanner: scanner)
                    case .appUpdater:
                        AppUpdaterChannelView(scanner: scanner)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [
                            selectedChannel.accentColor.opacity(0.05),
                            Color(nsColor: .windowBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

                // Toast Notification Banner when an action finishes
                if let status = scanner.lastStatusMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(status)
                            .font(.caption.weight(.semibold))
                        Button {
                            withAnimation {
                                scanner.lastStatusMessage = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .task {
            if scanner.junkItems.isEmpty && !scanner.isScanningJunk {
                await scanner.runSmartScan()
            }
        }
    }
}
