import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var scanner: DiskScannerService

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    public var body: some View {
        TabView {
            // Tab 1: General & Safety Preferences
            VStack(alignment: .leading, spacing: 18) {
                GlassCard(padding: 16, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Destino Padrão da Limpeza")
                            .font(.headline)

                        Picker("Destino:", selection: $scanner.removalMode) {
                            ForEach(RemovalMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(scanner.removalMode.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GlassCard(padding: 16, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle(isOn: $scanner.trashWatcherEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Vigia da Lixeira (Auto-Detect Uninstall)")
                                    .font(.headline)
                                Text("Detecta automaticamente quando um .app é jogado na Lixeira pelo Finder e oferece limpar os restos órfãos na ~/Library.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                GlassCard(padding: 16, cornerRadius: 14) {
                    HStack {
                        Image(systemName: scanner.hasFullDiskAccess ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                            .font(.title2)
                            .foregroundStyle(scanner.hasFullDiskAccess ? .green : .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Acesso Total ao Disco")
                                .font(.headline)
                            Text(scanner.hasFullDiskAccess ? "Liberado — o MeuCleaner enxerga todos os containers e caches." : "Opcional — libere nos Ajustes do Sistema para varreduras completas.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Abrir Ajustes") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Spacer()

                HStack {
                    Text("MeuCleaner Pro v1.1.0 (Build 2)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("Safe by default · 100% Local")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .tabItem {
                Label("Geral & Segurança", systemImage: "gearshape.fill")
            }

            // Tab 2: Lifetime Cleanup History
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(padding: 16, cornerRadius: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ESPAÇO TOTAL LIBERADO NESTE MAC")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(ByteFormatter.string(from: scanner.totalLifetimeFreedBytes))
                                .font(.system(size: 28, weight: .bold, design: .rounded))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Text("\(scanner.cleanupHistory.count) limpezas registradas")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if scanner.cleanupHistory.isEmpty {
                    Spacer()
                    ContentUnavailableView(
                        "Nenhuma limpeza registrada ainda",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("À medida que você limpar caches, restos ou duplicados, o histórico aparecerá aqui.")
                    )
                    Spacer()
                } else {
                    List(scanner.cleanupHistory) { record in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.channelTitle)
                                    .font(.subheadline.weight(.semibold))
                                Text("\(record.itemsCount) itens · \(record.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+\(ByteFormatter.string(from: record.freedBytes))")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(.green)
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .padding(20)
            .tabItem {
                Label("Histórico", systemImage: "chart.bar.fill")
            }
        }
        .frame(width: 540, height: 420)
    }
}
