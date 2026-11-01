import SwiftUI

struct StorageFindingRow: View {
    let item: StorageFinding
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(item.displayTitle).font(.headline)
                Spacer(minLength: 16)
                Text(sizeLabel).font(.subheadline.monospacedDigit())
            }
            Label(item.statusLabel, systemImage: item.canReviewRemoval ? "checklist" : "lock")
                .font(.caption.weight(.semibold))
                .foregroundStyle(item.canReviewRemoval ? Color.blue : Color.secondary)
            Text(item.consequence).font(.callout).foregroundStyle(.secondary)
            DisclosureGroup("Ver detalhes") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(item.reason)
                    Text(item.url.path).textSelection(.enabled)
                    if item.sharedBlocks { Text("Blocos compartilhados: ganho de espaço desconhecido. Não some cópias como espaço recuperável.") }
                    ForEach(item.measurement.issues, id: \.self) { Text($0) }
                    Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
                }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
            }.font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var sizeLabel: String {
        if !item.measurement.complete && item.measurement.allocatedBytes == 0 { return "Tamanho desconhecido" }
        return (item.measurement.complete ? "" : "Ao menos ") + ByteFormatter.string(from: item.measurement.allocatedBytes)
    }
}

struct CoverageSummary: View {
    @ObservedObject var scanner: DiskScannerService
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if scanner.isScanningJunk {
                HStack { ProgressView().controlSize(.small); Text("Analisando arquivos e verificando o uso…") }
                Text(scanner.lastScanDurationSeconds == nil
                     ? "Consultando locais conhecidos. Áreas sem acesso serão indicadas."
                     : "Os resultados anteriores permanecem visíveis até a análise terminar.").font(.caption).foregroundStyle(.secondary)
            } else if scanner.lastScanDurationSeconds == nil {
                Text("Análise ainda não realizada").foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("Última análise há")
                    Text(scanner.storageReport.scannedAt, style: .relative)
                    Text("· \(scanner.storageReport.coverageLabel)")
                }.font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("O que foi analisado") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A análise procura locais conhecidos. Não é uma leitura de todo o disco. Áreas fora deste catálogo não foram analisadas.")
                        Text("Sem acesso não significa vazio. Mais permissões não ampliam o catálogo de locais.")
                        ForEach(scanner.storageReport.issues, id: \.self) { Text($0).foregroundStyle(.orange) }
                        ForEach(scanner.storageReport.locationChecks) { check in
                            Text("\(check.state.rawValue) · \(check.path)").textSelection(.enabled)
                        }
                        Button("Entender e ajustar o acesso ao disco") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") { NSWorkspace.shared.open(url) }
                        }
                        Text("Opcional: autorizar o MeuCleaner nos Ajustes permite ler áreas protegidas. Isso não autoriza apagar arquivos.")
                    }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(.caption)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
