import SwiftUI

struct CleanupOverviewView: View {
    @ObservedObject var scanner: DiskScannerService
    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Analise → Revise → Limpe").font(.headline)
                HStack {
                    Button {
                        scanner.review(scanner.storageReport.findings(in: .chrome), title: "Cópias temporárias do Chrome")
                    } label: {
                        Label(scanner.isScanningJunk ? "Buscando cópias do Chrome..." : "Chrome · \(scanner.storageReport.findings(in: .chrome).count) cópias temporárias", systemImage: "doc.on.doc")
                    }.buttonStyle(.borderedProminent)
                    Button("Revisar arquivos e caches") {
                        scanner.review(scanner.storageReport.findings.filter { $0.category != nil }, title: "Arquivos e caches")
                    }.buttonStyle(.bordered)
                }.disabled(scanner.isScanningJunk || scanner.isCleaningJunk)
                Text("Nada é apagado ao analisar. Você escolhe os itens e vê o destino antes de confirmar; o uso é conferido novamente na limpeza.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct StorageGrowthView: View {
    @ObservedObject var scanner: DiskScannerService
    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("O que cresceu desde a última análise").font(.headline)
                if let previous = scanner.previousScanDate {
                    Text("Comparado com \(previous.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                    if scanner.storageGrowth.isEmpty {
                        Text("Nenhum aumento nos locais comparáveis desta análise.").font(.callout)
                    }
                    ForEach(scanner.storageGrowth.prefix(6)) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title).font(.subheadline)
                                Text(item.id).font(.caption2).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+" + ByteFormatter.string(from: item.delta)).foregroundStyle(.orange).monospacedDigit()
                        }
                    }
                } else {
                    Text("A primeira análise cria uma referência local. As próximas mostrarão aumentos medidos, sem inventar valores anteriores.").font(.callout)
                }
                Text("Compara apenas locais lidos por completo nas duas análises. Cópias APFS ficam fora da comparação. Não representa espaço recuperável.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
