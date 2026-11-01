import SwiftUI

struct CleanupReviewSheet: View {
    @ObservedObject var scanner: DiskScannerService
    let request: CleanupRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var mode: RemovalMode = .trash
    @State private var outcome: CleanupOutcome?

    private var fileMode: Bool { if case .files = request.target { return true }; return false }
    private var itemCount: String { "\(selection.count) \(selection.count == 1 ? "item" : "itens")" }
    private var permanentAction: String {
        switch request.target {
        case .files: return "Apagar \(itemCount) permanentemente"
        case .images: return "Remover \(selection.count) \(selection.count == 1 ? "imagem" : "imagens") Docker"
        case .buildCache: return "Remover cache de builds Docker"
        }
    }
    private var available: Set<String> {
        switch request.target {
        case .files(let files): return Set(files.filter(\.canReviewRemoval).map(\.id))
        case .images(let inventory): return Set(inventory.images.filter(\.canRemove).map(\.id))
        case .buildCache(let inventory): return inventory.oldCaches.isEmpty ? [] : ["build-cache"]
        }
    }
    private var summary: String {
        if case .files(let files) = request.target {
            let selected = files.filter { selection.contains($0.id) }
            if selected.contains(where: \.sharedBlocks) { return "\(itemCount) · ganho desconhecido por compartilhamento APFS" }
            return "\(itemCount) · \(ByteFormatter.string(from: selected.reduce(0) { $0 + $1.measurement.allocatedBytes })) medidos"
        }
        return "\(itemCount) · exclusão permanente pelo Docker"
    }
    private func toggle(_ id: String, allowed: Bool) -> Binding<Bool> {
        Binding(get: { selection.contains(id) }, set: { checked in
            if checked && allowed { selection.insert(id) } else { selection.remove(id) }
        })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(outcome == nil ? "Revisar: \(request.title)" : "Resultado da limpeza").font(.title2.bold())
            if let outcome { resultView(outcome) } else {
                Text("Escolha somente os itens que deseja remover. Itens em uso ou protegidos ficam bloqueados; o uso será verificado novamente antes de cada remoção.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    Button("Selecionar disponíveis (\(available.count))") { selection = available }
                    Button("Desmarcar tudo") { selection.removeAll() }
                    Spacer()
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }.disabled(scanner.isCleaningJunk || scanner.isScanningJunk)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) { reviewRows }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if fileMode {
                    Picker("Destino", selection: $mode) {
                        Text("Lixeira · permite restaurar").tag(RemovalMode.trash)
                        Text("Apagar permanentemente").tag(RemovalMode.permanent)
                    }.pickerStyle(.segmented).disabled(scanner.isCleaningJunk)
                    Text(mode == .trash ? "Mover para a Lixeira não libera espaço imediatamente." : "Exclusão sem Lixeira: estes arquivos não poderão ser restaurados pelo MeuCleaner.")
                        .font(.caption).foregroundStyle(mode == .trash ? Color.secondary : Color.orange)
                } else {
                    Text("O Docker não usa a Lixeira. Imagens podem exigir novo download ou recompilação; não há verificação de uso futuro por projetos. Volumes e containers são preservados.")
                        .font(.caption).foregroundStyle(.orange)
                }
                if scanner.isCleaningJunk {
                    HStack { ProgressView().controlSize(.small); Text(scanner.cleanupProgress).font(.caption) }
                }
                HStack {
                    Button("Cancelar") { dismiss() }.disabled(scanner.isCleaningJunk)
                    Spacer()
                    if fileMode && mode == .trash {
                        Button("Mover \(itemCount) para a Lixeira") { perform() }
                            .buttonStyle(.borderedProminent)
                            .disabled(selection.isEmpty || scanner.isCleaningJunk || scanner.isScanningJunk)
                    } else {
                        HoldToConfirmButton(title: "Segure: \(permanentAction)", symbol: "trash", holdDuration: 1.5,
                                            isDisabled: selection.isEmpty || scanner.isCleaningJunk || scanner.isScanningJunk) { perform() }
                    }
                }
            }
        }
        .padding(24).frame(width: 830, height: 650)
        .interactiveDismissDisabled(scanner.isCleaningJunk)
        .onAppear { selection = request.initialSelection.intersection(available) }
    }
    @ViewBuilder private var reviewRows: some View {
        switch request.target {
        case .files(let files):
            ForEach(files) { item in
                HStack(alignment: .top) {
                    Toggle("Selecionar \(item.title)", isOn: toggle(item.id, allowed: item.canReviewRemoval))
                        .labelsHidden().toggleStyle(.checkbox).disabled(!item.canReviewRemoval || scanner.isCleaningJunk)
                    StorageFindingRow(item: item)
                }
                Divider()
            }
        case .images(let inventory):
            ForEach(inventory.images) { image in
                HStack(alignment: .top) {
                    Toggle("Selecionar \(image.title)", isOn: toggle(image.id, allowed: image.canRemove))
                        .labelsHidden().toggleStyle(.checkbox).disabled(!image.canRemove || scanner.isCleaningJunk)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(image.title).font(.subheadline.weight(.semibold))
                        Text(image.canRemove ? "Revisar · nenhum container referencia esta imagem agora." : "Preservada · \(image.containers) containers referenciam esta imagem, inclusive parados.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Identificador técnico") { Text(image.id).font(.caption2).textSelection(.enabled) }
                    }
                    Spacer()
                    Text(ByteFormatter.string(from: image.size)).font(.caption)
                }
                Divider()
            }
        case .buildCache(let inventory):
            Toggle("Cache local sem uso há mais de 24 horas · \(inventory.oldCaches.count) registros", isOn: toggle("build-cache", allowed: !inventory.oldCaches.isEmpty))
                .toggleStyle(.checkbox).disabled(inventory.oldCaches.isEmpty || scanner.isCleaningJunk)
            Text("A operação será limitada aos registros desta revisão que continuarem sem uso. Builds futuros podem demorar mais.").font(.caption)
        }
    }
    private func perform() {
        Task {
            outcome = await scanner.performReviewedCleanup(request, selection: selection.intersection(available), mode: mode)
            // Refresh actual measurements and Docker state even if a command timed out.
            await scanner.runSmartScan()
        }
    }
    private func resultView(_ result: CleanupOutcome) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(result.rows.filter(\.success).count) operações confirmadas · \(result.rows.filter { !$0.success }.count) preservadas ou não confirmadas").font(.headline)
            Text(result.note).font(.caption).foregroundStyle(.secondary)
            Text("Espaço livre observado: \(ByteFormatter.string(from: result.freeBefore)) antes → \(ByteFormatter.string(from: result.freeAfter)) depois").font(.caption)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(result.rows) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(row.title, systemImage: row.success ? "checkmark.circle" : "exclamationmark.shield")
                                .foregroundStyle(row.success ? Color.green : Color.orange)
                            Text(row.message).font(.caption).textSelection(.enabled)
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if scanner.isScanningJunk { Text("Atualizando o diagnóstico...").font(.caption) }
            HStack {
                if fileMode && mode == .trash && scanner.canUndoLastCleanup {
                    Button("Desfazer envio à Lixeira") { Task { await scanner.undoLastCleanup(); dismiss() } }
                        .disabled(scanner.isScanningJunk)
                }
                Spacer()
                Button("Concluir") { dismiss() }.buttonStyle(.borderedProminent)
            }
        }
    }
}
