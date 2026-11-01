import SwiftUI

public struct HomeChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @ObservedObject public var monitor: SystemMonitorService
    @Binding public var selectedChannel: CleanerChannel
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Visão geral").font(.largeTitle.bold())
                GlassCard(padding: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Armazenamento do Mac", systemImage: "internaldrive.fill")
                            .font(.headline).foregroundStyle(.cyan)
                        Text("\(ByteFormatter.string(from: monitor.diskFreeBytes)) disponíveis")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text("de \(ByteFormatter.string(from: monitor.diskTotalBytes)) no Mac").foregroundStyle(.secondary)
                        ProgressView(value: monitor.diskUsedPercent, total: 100).tint(.cyan)
                        Text("Disponibilidade informada pelo macOS. Não é uma estimativa do que a limpeza vai liberar.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button(scanner.isScanningJunk ? "Analisando…" : "Analisar Mac") {
                                Task { await scanner.runSmartScan() }
                            }.buttonStyle(.borderedProminent).controlSize(.large)
                                .disabled(scanner.isScanningJunk || scanner.isCleaningJunk)
                            if scanner.lastScanDurationSeconds != nil {
                                Button("Revisar itens encontrados") { selectedChannel = .developerStorage }
                                    .controlSize(.large).disabled(scanner.isScanningJunk || scanner.isCleaningJunk)
                            }
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Analisar não apaga nada. Você escolhe os itens antes de confirmar.")
                                .font(.callout).foregroundStyle(.secondary)
                            CoverageSummary(scanner: scanner)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                DashboardMetrics(monitor: monitor)
                DashboardTools(selectedChannel: $selectedChannel)
                if scanner.lastScanDurationSeconds != nil {
                    HStack(alignment: .top, spacing: 24) {
                        summary("Recomendados para revisão", value: itemCount(scanner.storageReport.findings.filter { $0.canReviewRemoval && $0.disposition == .candidate }.count, singular: "item", plural: "itens"),
                                detail: "\(ByteFormatter.string(from: scanner.storageReport.candidateMeasuredBytes)) medidos · ganho ainda não confirmado")
                        summary("Preservados ou em uso", value: itemCount(scanner.storageReport.findings.filter { $0.disposition == .protected || $0.disposition == .inUse }.count, singular: "local", plural: "locais"),
                                detail: "Continuam visíveis para explicar a ocupação do disco.")
                    }
                    if scanner.storageReport.findings.contains(where: { $0.sharedBlocks }) {
                        Button("Revisar cópias temporárias do Chrome · ganho de espaço desconhecido") { selectedChannel = .developerStorage }
                    }
                    HStack {
                        Text("O que mais ocupa espaço").font(.title2.bold())
                        Spacer()
                        Button("Explorar pastas") { selectedChannel = .spaceLens }
                    }
                    Text("Maiores locais encontrados, incluindo dados preservados. Não representa todo o disco nem espaço recuperável.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(scanner.storageReport.largestLocations.prefix(8)) { item in
                        GlassCard { StorageFindingRow(item: item) }
                    }
                    if scanner.storageReport.findings.isEmpty {
                        Text("Nenhum item foi encontrado nos locais analisados. Confira os limites de acesso acima.")
                    }
                }
            }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
        .onAppear { monitor.isDashboardActive = true; monitor.refreshAll() }
        .onDisappear { monitor.isDashboardActive = false }
    }
    private func itemCount(_ count: Int, singular: String, plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
    }
    private func summary(_ title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text(value).font(.title2.bold())
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
