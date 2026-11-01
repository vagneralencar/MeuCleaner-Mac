import SwiftUI

struct StorageReportView: View {
    let report: StorageReport
    private func color(_ state: StorageDisposition) -> Color {
        switch state {
        case .candidate: return .green
        case .review: return .orange
        case .inUse: return .blue
        case .protected: return .secondary
        case .unverified: return .red
        }
    }
    var body: some View {
        GlassCard(padding: 16, cornerRadius: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("O que pode ser limpo e o que deve ser preservado").font(.headline)
                Text("Candidatos: \(ByteFormatter.string(from: report.candidateMeasuredBytes)) medidos. Isso não garante o mesmo ganho de espaço: cópias APFS compartilham blocos e mover para a Lixeira não libera espaço imediatamente.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(StorageDisposition.allCases, id: \.self) { state in
                    let findings = report.findings.filter { $0.disposition == state }
                    if !findings.isEmpty {
                        DisclosureGroup("\(state.rawValue) · \(findings.count) itens") {
                            ForEach(findings) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.title).font(.subheadline.weight(.semibold))
                                        Text(item.reason).font(.caption).foregroundStyle(.secondary)
                                        Text(item.url.path).font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing) {
                                        Text(ByteFormatter.string(from: item.measurement.allocatedBytes)).monospacedDigit()
                                        if item.sharedBlocks { Text("Ganho desconhecido").font(.caption2) }
                                        if !item.measurement.complete { Text("Leitura parcial").font(.caption2) }
                                        Button("Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.controlSize(.small)
                                    }
                                }.padding(.vertical, 5)
                            }
                        }.tint(color(state))
                    }
                }
                Divider()
                Text("Docker · somente leitura").font(.subheadline.weight(.semibold))
                ForEach(report.dockerRows) { row in
                    HStack {
                        Text(row.displayName)
                        Spacer()
                        Text("\(row.active)/\(row.count) ativos · \(row.size)")
                        Text("Recuperável: \(row.reclaimable)").foregroundStyle(.secondary)
                    }.font(.caption)
                }
                Text(report.dockerNote).font(.caption).foregroundStyle(.secondary)
                Divider()
                Text("Runtimes dos simuladores Apple").font(.subheadline.weight(.semibold))
                ForEach(report.simulatorRuntimes) { runtime in
                    HStack {
                        Text("Versão \(runtime.version)")
                        Spacer()
                        Text(ByteFormatter.string(from: runtime.sizeBytes)).monospacedDigit()
                        Text("Último uso: \(runtime.lastUsed)").foregroundStyle(.secondary)
                    }.font(.caption)
                }
                Text(report.simulatorNote).font(.caption).foregroundStyle(.secondary)
                if !report.issues.isEmpty {
                    DisclosureGroup("Limites da análise · \(report.issues.count) avisos") {
                        ForEach(report.issues, id: \.self) { issue in
                            Text(issue).font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Text("Acesso Total ao Disco pode permitir ler pastas protegidas pelo macOS. Uma falha de leitura nunca significa que a pasta está vazia.").font(.caption)
                    }.tint(.orange)
                }
            }
        }
    }
}
