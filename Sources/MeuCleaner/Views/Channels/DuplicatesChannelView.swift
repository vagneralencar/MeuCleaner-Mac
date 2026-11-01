import SwiftUI

public struct DuplicatesChannelView: View {
    @ObservedObject public var scanner: DiskScannerService

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .duplicates,
                trailingBadgeText: scanner.hasScannedDuplicates ? "\(scanner.duplicateGroups.count) grupos" : nil,
                actionTitle: scanner.isScanningDuplicates ? "Comparando arquivos…" : "Buscar duplicados",
                isLoading: scanner.isScanningDuplicates,
                onAction: {
                    Task { await scanner.scanDuplicateFiles() }
                }
            )

            Text("Downloads, Filmes, Música, Imagens e Público · arquivos a partir de 1 MB. Escolha quais cópias manter antes de revisar a remoção.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(alignment: .top) {
                DisclosureGroup("Como os arquivos são comparados") {
                    Text("Comparamos tamanho, uma amostra e o conteúdo completo (SHA-256). Arquivos ocultos, pacotes e a biblioteca de Fotos não entram nesta busca. Os tamanhos são dos arquivos; não representam espaço garantido após a remoção.")
                        .font(.caption).foregroundStyle(.secondary)
                }.font(.caption)

                Spacer()

                if !scanner.duplicateGroups.isEmpty {
                    Button {
                        scanner.autoSelectDuplicatesKeepingNewest()
                    } label: {
                        Label("Selecionar cópias mais antigas", systemImage: "checklist")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    .controlSize(.small)
                }
            }

            if !scanner.duplicateScanIssues.isEmpty {
                DisclosureGroup("Busca parcial · \(scanner.duplicateScanIssues.count) \(scanner.duplicateScanIssues.count == 1 ? "aviso" : "avisos") de leitura") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(scanner.duplicateScanIssues, id: \.self) { Text($0).font(.caption).textSelection(.enabled) }
                        }
                    }.frame(maxHeight: 140)
                }.font(.caption).foregroundStyle(.orange)
            }

            if scanner.isScanningDuplicates {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Comparando o conteúdo dos arquivos… Nenhum arquivo será apagado.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if scanner.duplicateGroups.isEmpty {
                Spacer()
                ContentUnavailableView(
                    !scanner.hasScannedDuplicates ? "Busque arquivos duplicados" : (scanner.duplicateScanIssues.isEmpty ? "Nenhuma cópia idêntica encontrada" : "Nenhuma cópia identificada na parte analisada"),
                    systemImage: "doc.on.doc",
                    description: Text(!scanner.hasScannedDuplicates ? "A busca compara os arquivos das pastas indicadas acima." : "O resultado se limita aos arquivos que puderam ser lidos. Pastas fora desta busca não foram analisadas.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(scanner.duplicateGroups) { group in
                            GlassCard(padding: 14, cornerRadius: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "doc.on.doc.fill")
                                            .foregroundStyle(.teal)
                                        Text("\(group.files.count) cópias idênticas · \(ByteFormatter.string(from: group.eachFileSizeBytes)) cada")
                                            .font(.subheadline.weight(.bold))

                                        Spacer()

                                        Text("Selecionado: \(ByteFormatter.string(from: group.selectedReclaimableBytes))")
                                            .font(.system(.caption, design: .monospaced).weight(.bold))
                                            .foregroundStyle(.teal)
                                    }

                                    Divider()

                                    ForEach(Array(group.files.enumerated()), id: \.element.id) { fileIdx, file in
                                        HStack(spacing: 10) {
                                            Toggle("Selecionar \(file.name)", isOn: Binding(
                                                get: { file.isSelectedForRemoval },
                                                set: { val in
                                                    scanner.setDuplicateSelection(groupID: group.id, fileID: file.id, selected: val)
                                                }
                                            ))
                                            .toggleStyle(.checkbox)
                                            .labelsHidden()

                                            if fileIdx == 0 && !file.isSelectedForRemoval {
                                                Text("Manter (Mais recente)")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.green.opacity(0.16), in: Capsule())
                                                    .foregroundStyle(.green)
                                            } else if file.isSelectedForRemoval {
                                                Text("Remover cópia")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.red.opacity(0.16), in: Capsule())
                                                    .foregroundStyle(.red)
                                            }

                                            Text(file.url.path)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            Spacer()

                                            Text(file.modifiedDate.formatted(date: .abbreviated, time: .omitted))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)

                                            Button {
                                                NSWorkspace.shared.open(file.url)
                                            } label: {
                                                Image(systemName: "eye")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Abrir ou pré-visualizar cópia")

                                            Button {
                                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                            } label: {
                                                Image(systemName: "magnifyingglass")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.borderless)
                                            .help("Revelar no Finder")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                SafetyNoticePill(text: "Mantenha pelo menos uma cópia de cada grupo. A próxima etapa mostra os itens e o destino.")
                Spacer()
                Button {
                    Task { _ = await scanner.cleanSelectedDuplicates() }
                } label: {
                    Label(
                        "Revisar cópias (\(ByteFormatter.string(from: scanner.selectedDuplicatesReclaimableBytes)))",
                        systemImage: "trash"
                    )
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(scanner.selectedDuplicatesReclaimableBytes == 0 || scanner.isScanningDuplicates || scanner.isScanningJunk || scanner.isCleaningJunk || scanner.isRestoring)
            }
        }
        .padding(24)
        .task {
            if !scanner.hasScannedDuplicates && !scanner.isScanningDuplicates {
                await scanner.scanDuplicateFiles()
            }
        }
    }
}
