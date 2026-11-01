import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var scanner: DiskScannerService
    @ObservedObject public var updater: SelfUpdaterService

    public init(scanner: DiskScannerService, updater: SelfUpdaterService) {
        self.scanner = scanner
        self.updater = updater
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
                    Text("MeuCleaner Pro v\(updater.currentVersion) (Build \(updater.currentBuild))")
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

            // Historical figures describe processed items, not guaranteed physical space gains.
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(padding: 16, cornerRadius: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TAMANHO DOS ITENS PROCESSADOS")
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

                Text("Inclui itens enviados à Lixeira. Tamanhos históricos não equivalem ao espaço livre ganho, especialmente com cópias APFS.")
                    .font(.caption).foregroundStyle(.secondary)

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
                            Text(ByteFormatter.string(from: record.freedBytes))
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

            // Tab 3: Automatic Updates for MeuCleaner
            VStack(alignment: .leading, spacing: 16) {
                GlassCard(padding: 16, cornerRadius: 14) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .center) {
                            Image(systemName: "sparkles")
                                .font(.title2)
                                .foregroundStyle(.blue)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("MeuCleaner Pro")
                                    .font(.headline)
                                Text("Versão instalada: v\(updater.currentVersion) (Build \(updater.currentBuild))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Button {
                                Task { await updater.checkForUpdates(silent: false) }
                            } label: {
                                if updater.isChecking {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Label("Buscar Atualizações", systemImage: "arrow.triangle.2.circlepath")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(updater.isChecking || updater.isDownloading)
                        }

                        Divider()

                        Toggle(isOn: $updater.autoCheckOnLaunch) {
                            Text("Verificar atualizações automaticamente ao iniciar")
                                .font(.subheadline)
                        }
                        .toggleStyle(.checkbox)

                        if let lastCheck = updater.lastCheckDate {
                            Text("Última verificação: \(lastCheck.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let update = updater.availableUpdate {
                    GlassCard(padding: 16, cornerRadius: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Nova versão v\(update.version) disponível!")
                                        .font(.headline)
                                        .foregroundStyle(.green)
                                    Text(update.title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if update.assetSizeBytes > 0 {
                                    Text(ByteFormatter.string(from: update.assetSizeBytes))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if !update.releaseNotes.isEmpty {
                                ScrollView {
                                    Text(update.releaseNotes)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(8)
                                }
                                .frame(height: 70)
                                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                            }

                            if updater.isDownloading {
                                VStack(alignment: .leading, spacing: 4) {
                                    ProgressView(value: updater.downloadProgress, total: 1.0)
                                        .tint(.green)
                                    Text("Baixando: \(Int(updater.downloadProgress * 100))%")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 10) {
                                Button {
                                    Task { await updater.downloadAndInstallUpdate() }
                                } label: {
                                    Label(
                                        updater.isInstalling ? "Instalando..." : (updater.isDownloading ? "Baixando..." : "Atualizar Agora"),
                                        systemImage: "bolt.fill"
                                    )
                                    .fontWeight(.semibold)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                                .disabled(updater.isDownloading || updater.isInstalling)

                                Button("Ver no GitHub") {
                                    NSWorkspace.shared.open(update.htmlURL)
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                } else if let msg = updater.statusMessage {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        Text(msg)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                }

                Spacer()
            }
            .padding(20)
            .tabItem {
                Label("Atualizações", systemImage: "arrow.triangle.2.circlepath.circle.fill")
            }
        }
        .frame(width: 540, height: 440)
    }
}
