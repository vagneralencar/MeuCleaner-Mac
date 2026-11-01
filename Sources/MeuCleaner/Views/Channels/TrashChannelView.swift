import SwiftUI

public struct TrashChannelView: View {
    @ObservedObject public var scanner: DiskScannerService

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .trash,
                trailingBadgeText: scanner.hasScannedTrash ? ByteFormatter.string(from: scanner.totalTrashBytes) : "Não verificado",
                actionTitle: scanner.isScanningTrash ? "Lendo..." : "Atualizar Lixeira",
                isLoading: scanner.isScanningTrash,
                onAction: {
                    Task { await scanner.scanTrash() }
                }
            )

            if scanner.isScanningTrash {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView("Lendo itens na Lixeira do macOS...")
                    Spacer()
                }
                Spacer()
            } else if !scanner.hasScannedTrash {
                ContentUnavailableView("Não foi possível verificar a Lixeira", systemImage: "lock",
                    description: Text(scanner.trashScanIssue ?? "Atualize a análise para verificar o conteúdo. Nenhum tamanho foi confirmado."))
                Text("Sem acesso não significa vazio. Você pode conferir os itens diretamente no Finder.").font(.callout).foregroundStyle(.secondary)
                Button("Abrir Lixeira no Finder") {
                    NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                }
                Spacer()
            } else if scanner.trashItems.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Sua Lixeira está vazia",
                    systemImage: "trash.slash",
                    description: Text("Os itens removidos com o destino Lixeira aparecem aqui. Exclusões permanentes não passam pela Lixeira.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(scanner.trashItems) { item in
                            GlassCard(padding: 12, cornerRadius: 12) {
                                HStack(spacing: 12) {
                                    Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                                        .font(.system(size: 16))
                                        .foregroundStyle(.pink)
                                        .frame(width: 30, height: 30)
                                        .background(Color.pink.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        if let date = item.deletedDate {
                                            Text("Adicionado em \(date.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Text(ByteFormatter.string(from: item.sizeBytes))
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))

                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                    } label: {
                                        Label("Ver na Lixeira", systemImage: "arrow.uturn.backward")
                                            .font(.caption2)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Abrir na Lixeira do Finder para restaurar")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundStyle(.red)
                    Text("Esvaziar apaga de vez: mantenha o botão pressionado até a barra completar. Um clique solto não apaga nada.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()

                HoldToConfirmButton(
                    title: scanner.hasScannedTrash ? "Segure para Esvaziar (\(ByteFormatter.string(from: scanner.totalTrashBytes)))" : "Verifique a Lixeira primeiro",
                    symbol: "flame.fill",
                    holdDuration: 1.5,
                    isDisabled: !scanner.hasScannedTrash || scanner.isScanningTrash || scanner.trashItems.isEmpty || scanner.isCleaningJunk || scanner.isRestoring
                ) {
                    Task {
                        await scanner.emptyTrashPermanently()
                    }
                }
            }
        }
        .padding(24)
        .task {
            if scanner.trashItems.isEmpty && !scanner.isScanningTrash {
                await scanner.scanTrash()
            }
        }
    }
}
