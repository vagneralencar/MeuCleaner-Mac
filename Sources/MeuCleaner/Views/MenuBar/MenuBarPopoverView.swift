import SwiftUI

public struct MenuBarPopoverView: View {
    @ObservedObject public var monitor: SystemMonitorService
    @ObservedObject public var scanner: DiskScannerService
    @ObservedObject public var updater: SelfUpdaterService
    @Environment(\.openWindow) private var openWindow

    public init(
        monitor: SystemMonitorService,
        scanner: DiskScannerService,
        updater: SelfUpdaterService
    ) {
        self.monitor = monitor
        self.scanner = scanner
        self.updater = updater
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.blue)
                    Text("MeuCleaner")
                        .font(.headline.bold())
                }
                Spacer()
                Text("Agente Ativo")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }

            if let update = updater.availableUpdate {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                    Text("Atualização v\(update.version) pronta")
                        .font(.caption.weight(.bold))
                    Spacer()
                    Button("Instalar") {
                        Task { await updater.downloadAndInstallUpdate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .tint(.green)
                }
                .padding(8)
                .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            // Metrics Grid: CPU, RAM, Disk, Battery & Network
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                MetricMiniCard(
                    title: "CPU",
                    value: String(format: "%.0f%%", monitor.cpuUsagePercent),
                    subtitle: "Processador",
                    symbol: "cpu.fill",
                    color: .blue
                )

                MetricMiniCard(
                    title: "MEMÓRIA",
                    value: String(format: "%.0f%%", monitor.memoryPressurePercent),
                    subtitle: ByteFormatter.string(from: monitor.memoryUsedBytes),
                    symbol: "memorychip.fill",
                    color: .purple
                )

                MetricMiniCard(
                    title: "DISCO LIVRE",
                    value: ByteFormatter.string(from: monitor.diskFreeBytes),
                    subtitle: "de \(ByteFormatter.string(from: monitor.diskTotalBytes))",
                    symbol: "internaldrive.fill",
                    color: .cyan
                )

                MetricMiniCard(
                    title: "BATERIA & REDE",
                    value: "\(monitor.batteryPercent)%\(monitor.isCharging ? " ⚡︎" : "")",
                    subtitle: "↓ \(ByteFormatter.string(from: monitor.networkDownBytesPerSec))/s",
                    symbol: monitor.isCharging ? "battery.100.bolt" : "battery.100",
                    color: .green
                )
            }

            Divider()

            // Top Memory Hogs
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("APPS QUE MAIS USAM MEMÓRIA")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        monitor.refreshAll()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                }

                ForEach(monitor.topMemoryApps.prefix(4)) { app in
                    HStack(spacing: 8) {
                        if let icon = app.icon {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "app.fill")
                                .frame(width: 18, height: 18)
                        }

                        Text(app.name)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)

                        Spacer()

                        Text(ByteFormatter.string(from: app.memoryBytes))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Button("Encerrar") {
                            monitor.terminateApp(pid: app.id)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                }
            }

            Divider()

            // Quick Actions
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        Task {
                            if scanner.junkItems.isEmpty {
                                await scanner.scanSystemJunk()
                            }
                            _ = await scanner.cleanSelectedJunk()
                        }
                    } label: {
                        Label("Limpar Lixo", systemImage: "sparkles")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)

                    Button {
                        NSApp.activate(ignoringOtherApps: true)
                    } label: {
                        Label("Abrir Painel", systemImage: "macwindow")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            monitor.isPopoverActive = true
            monitor.refreshAll(forceHeavyTasks: true)
        }
        .onDisappear {
            monitor.isPopoverActive = false
        }
    }
}

private struct MetricMiniCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
