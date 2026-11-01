import SwiftUI

struct DeveloperStorageChannelView: View {
    @ObservedObject var scanner: DiskScannerService
    let reviewCaches: () -> Void
    @State private var environment: StorageEnvironment = .chrome

    private var report: StorageReport { scanner.storageReport }
    private var items: [StorageFinding] { report.findings(in: environment) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(channel: .developerStorage,
                              actionTitle: scanner.isScanningJunk ? "Analisando..." : "Atualizar análise",
                              isLoading: scanner.isScanningJunk) {
                Task { await scanner.runSmartScan() }
            }
            Picker("Ambiente", selection: $environment) {
                ForEach(StorageEnvironment.allCases) { group in
                    Text(group.rawValue).tag(group)
                }
            }
            .pickerStyle(.segmented)

            Text("1 · Analise   →   2 · Revise os itens   →   3 · Confirme a limpeza. O uso será verificado novamente antes de apagar.")
                .font(.caption).foregroundStyle(.secondary)

            if scanner.isScanningJunk {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(scanner.lastScanDurationSeconds == nil ? "Consultando ferramentas e medindo arquivos..." : "Atualizando; os dados abaixo são da análise anterior.")
                        .font(.caption)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if environment == .chrome {
                        GlassCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(scanner.lastScanDurationSeconds == nil ? "Buscando cópias temporárias do Chrome..." : "Cópias temporárias do Chrome · \(items.count) encontradas").font(.headline)
                                Text("São cópias do aplicativo, não seu perfil, senhas ou favoritos. Cada cópia será conferida novamente antes de remover.")
                                Text("Ganho de espaço desconhecido: as cópias APFS compartilham blocos. Os tamanhos individuais não devem ser somados como espaço recuperável.").foregroundStyle(.secondary)
                            }.font(.callout)
                        }
                    }
                    if environment == .docker { dockerSummary }
                    if environment == .xcode { runtimeSummary }
                    if scanner.lastScanDurationSeconds != nil {
                        inventory
                    }
                    if !report.issues.isEmpty {
                        GlassCard(padding: 14) {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Cobertura incompleta · \(report.issues.count) avisos", systemImage: "exclamationmark.triangle")
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                                DisclosureGroup("Ver locais não verificados") {
                                    ForEach(report.issues, id: \.self) { issue in
                                        Text(issue).font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(items.filter(\.canReviewRemoval).count) itens disponíveis para revisão")
                    Text("Itens em uso, projetos e dados protegidos ficam bloqueados.").foregroundStyle(.secondary)
                }.font(.caption)
                Spacer()
                Button("Revisar e limpar") {
                    scanner.review(items, title: environment.rawValue)
                }
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty || scanner.isScanningJunk || scanner.isCleaningJunk)
            }
        }
        .padding(24)
    }

    private var dockerSummary: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Docker · imagens, containers, volumes e builds").font(.headline)
                if let inventory = report.dockerInventory {
                    HStack {
                        Button("Revisar \(inventory.images.filter(\.canRemove).count) imagens sem containers") {
                            scanner.cleanupRequest = CleanupRequest(title: "Imagens Docker", target: .images(inventory))
                        }.disabled(scanner.isScanningJunk || scanner.isCleaningJunk)
                        Button("Revisar cache de builds") {
                            scanner.cleanupRequest = CleanupRequest(title: "Cache de builds Docker", target: .buildCache(inventory))
                        }.disabled(inventory.oldCaches.isEmpty || scanner.isScanningJunk || scanner.isCleaningJunk)
                    }.buttonStyle(.bordered)
                    if inventory.oldCaches.isEmpty {
                        Text("Nenhum cache de builds sem uso há mais de 24 horas foi identificado.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Limpeza Docker indisponível até validar o inventário e o destino local.").font(.caption).foregroundStyle(.orange)
                }
                ForEach(report.dockerRows) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.displayName).font(.subheadline.weight(.semibold))
                            Text("\(row.active) ativos de \(row.count)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(row.size).monospacedDigit()
                            Text("Estimativa recuperável: \(row.reclaimable)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Imagens só são removidas após sua escolha e nova verificação de containers ativos e parados. Volumes e containers não são apagados por este fluxo.").font(.caption).foregroundStyle(.secondary)
                Text("O disco virtual abaixo contém estes dados. Não some os dois tamanhos. Volumes podem guardar bancos de dados, mesmo quando não estão em uso.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var runtimeSummary: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Xcode · runtimes dos simuladores").font(.headline)
                ForEach(report.simulatorRuntimes) { runtime in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Versão \(runtime.version)").font(.subheadline.weight(.semibold))
                            Text("Último uso: \(runtime.lastUsed)").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(ByteFormatter.string(from: runtime.sizeBytes)).monospacedDigit()
                    }
                }
                Text(report.simulatorNote).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var inventory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(environment.rawValue) · arquivos e dados locais (\(items.count))").font(.headline)
            if items.isEmpty {
                Text("Nenhum local com espaço ocupado foi identificado nesta categoria. Consulte os avisos de acesso: isso não confirma ausência de dados em locais não verificados.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(items) { item in
                GlassCard(padding: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                            Text(item.disposition.rawValue).font(.caption.weight(.semibold))
                                .foregroundStyle(item.disposition.allowsSelection ? Color.orange : Color.secondary)
                            Text(item.reason).font(.caption).foregroundStyle(.secondary)
                            Text(item.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            Text(ByteFormatter.string(from: item.measurement.allocatedBytes)).monospacedDigit()
                            if !item.measurement.complete { Text("Leitura parcial").font(.caption2) }
                            Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}
