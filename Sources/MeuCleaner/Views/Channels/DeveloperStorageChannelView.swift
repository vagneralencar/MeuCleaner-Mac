import SwiftUI

struct DeveloperStorageChannelView: View {
    @ObservedObject var scanner: DiskScannerService
    let reviewCaches: () -> Void
    @State private var environment: StorageEnvironment?
    @State private var search = ""
    @State private var selection: Set<String> = []
    @State private var expanded: Set<ReviewGroup> = [.recommended, .attention, .unknown]
    private var report: StorageReport { scanner.storageReport }
    private var items: [StorageFinding] {
        report.findings.filter { item in
            let group = StorageEnvironment.classify(item)
            let matches = environment == nil || group == environment || (environment == .other && group == nil)
            return matches && (search.isEmpty || item.displayTitle.localizedCaseInsensitiveContains(search) || item.url.path.localizedCaseInsensitiveContains(search))
        }
    }
    private var chosen: [StorageFinding] { report.findings.filter { selection.contains($0.id) && $0.canReviewRemoval } }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(channel: .developerStorage,
                              actionTitle: scanner.isScanningJunk ? "Analisando…" : "Analisar novamente",
                              isLoading: scanner.isScanningJunk) { Task { await scanner.runSmartScan() } }
            HStack {
                Picker("Aplicativo", selection: $environment) {
                    Text("Todos").tag(StorageEnvironment?.none)
                    ForEach(StorageEnvironment.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }.pickerStyle(.segmented)
                TextField("Buscar item", text: $search).textFieldStyle(.roundedBorder).frame(maxWidth: 190)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    CoverageSummary(scanner: scanner)
                    if scanner.lastScanDurationSeconds != nil {
                        if environment == nil || environment == .docker { dockerSummary }
                        if environment == .xcode {
                            DisclosureGroup("Runtimes de simuladores · preservados") { runtimeSummary }
                        }
                        if items.isEmpty {
                            ContentUnavailableView("Nenhum resultado neste filtro", systemImage: "magnifyingglass",
                                description: Text("Ajuste a busca ou confira os locais analisados. Isso não confirma que o aplicativo não ocupe espaço."))
                        }
                        ForEach(ReviewGroup.allCases) { group in
                            let grouped = items.filter { group.contains($0) }
                            if !grouped.isEmpty {
                                DisclosureGroup(isExpanded: Binding(get: { expanded.contains(group) }, set: {
                                    if $0 { expanded.insert(group) } else { expanded.remove(group) }
                                })) {
                                    VStack(spacing: 12) {
                                        ForEach(grouped) { item in
                                            GlassCard {
                                                HStack(alignment: .top, spacing: 12) {
                                                    Toggle("Selecionar \(item.displayTitle)", isOn: Binding(
                                                        get: { selection.contains(item.id) },
                                                        set: { if $0 && item.canReviewRemoval { selection.insert(item.id) } else { selection.remove(item.id) } }
                                                    )).labelsHidden().toggleStyle(.checkbox)
                                                        .disabled(!item.canReviewRemoval || scanner.isScanningJunk || scanner.isCleaningJunk)
                                                    StorageFindingRow(item: item)
                                                }
                                            }
                                        }
                                    }.padding(.top, 10)
                                } label: { Text("\(group.rawValue) · \(grouped.count)").font(.headline) }
                            }
                        }
                    } else if !scanner.isScanningJunk {
                        ContentUnavailableView("Comece analisando o Mac", systemImage: "sparkles",
                            description: Text("A análise encontra dados, verifica o uso e não apaga arquivos."))
                    }
                }.padding(.vertical, 4)
            }
            Divider()
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(chosen.count == 1 ? "1 item selecionado" : "\(chosen.count) itens selecionados").font(.headline)
                    Text("A próxima etapa mostra o destino. Nenhum arquivo foi apagado.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("Selecionar recomendados deste filtro") {
                            selection.formUnion(items.filter { $0.disposition == .candidate && $0.canReviewRemoval }.map(\.id))
                        }
                        Button("Desmarcar tudo") { selection.removeAll() }
                    }.controlSize(.small).disabled(scanner.isScanningJunk || scanner.isCleaningJunk)
                }
                Spacer()
                Button("Revisar \(chosen.count) \(chosen.count == 1 ? "item" : "itens")") {
                    scanner.review(chosen, title: "Arquivos selecionados", selection: Set(chosen.map(\.id)))
                }.buttonStyle(.borderedProminent)
                    .disabled(chosen.isEmpty || scanner.isScanningJunk || scanner.isCleaningJunk)
            }
        }.padding(24)
        .onChange(of: report.scannedAt) { _, _ in selection.removeAll() }
    }

    private var dockerSummary: some View {
        GlassCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Docker · imagens, containers, volumes e builds").font(.headline)
                if let inventory = report.dockerInventory {
                    HStack {
                        Button("Revisar \(inventory.images.filter(\.canRemove).count) imagens sem containers") {
                            scanner.cleanupRequest = CleanupRequest(title: "Imagens Docker", target: .images(inventory))
                        }.disabled(inventory.images.filter(\.canRemove).isEmpty || scanner.isScanningJunk || scanner.isCleaningJunk)
                        Button("Revisar cache de builds") {
                            scanner.cleanupRequest = CleanupRequest(title: "Cache de builds Docker", target: .buildCache(inventory))
                        }.disabled(inventory.oldCaches.isEmpty || scanner.isScanningJunk || scanner.isCleaningJunk)
                    }.buttonStyle(.bordered)
                    if inventory.oldCaches.isEmpty {
                        Text("Nenhum cache de builds sem uso há mais de 24 horas foi identificado.").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Limpeza Docker indisponível até validar o inventário e o destino local.").font(.caption).foregroundStyle(.orange)
                    Text(report.dockerNote).font(.caption).foregroundStyle(.secondary)
                    Text("Confira se o Docker Desktop está aberto e tente analisar novamente. O MeuCleaner não inicia serviços automaticamente.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                DisclosureGroup("Ocupação e limites do Docker") {
                ForEach(report.issues.filter { $0.localizedCaseInsensitiveContains("docker") }, id: \.self) { issue in
                    Text(issue).font(.caption).foregroundStyle(.orange)
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

}
