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
                trailingBadgeText: "\(ByteFormatter.string(from: scanner.selectedDuplicatesReclaimableBytes)) / \(ByteFormatter.string(from: scanner.totalDuplicatesReclaimableBytes))",
                actionTitle: scanner.isScanningDuplicates ? "Comparando Hashes..." : "Buscar Duplicados",
                isLoading: scanner.isScanningDuplicates,
                onAction: {
                    Task { await scanner.scanDuplicateFiles() }
                }
            )

            HStack {
                Text("Algoritmo em 3 estágios: Tamanho exato em bytes → Hash parcial de 64 KB → Hash completo SHA-256.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if !scanner.duplicateGroups.isEmpty {
                    Button {
                        scanner.autoSelectDuplicatesKeepingNewest()
                    } label: {
                        Label("Manter Apenas o Mais Recente", systemImage: "wand.and.stars")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.teal)
                    .controlSize(.small)
                }
            }

            if scanner.isScanningDuplicates {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Verificando impressões digitais SHA-256 nas suas pastas...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if scanner.duplicateGroups.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nenhum arquivo duplicado encontrado",
                    systemImage: "doc.on.doc",
                    description: Text("Não há arquivos idênticos (≥ 1 MB) nas pastas Downloads, Filmes, Música, Imagens e Público.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(scanner.duplicateGroups.enumerated()), id: \.element.id) { groupIdx, group in
                            GlassCard(padding: 14, cornerRadius: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Image(systemName: "doc.on.doc.fill")
                                            .foregroundStyle(.teal)
                                        Text("\(group.files.count) cópias idênticas · \(ByteFormatter.string(from: group.eachFileSizeBytes)) cada")
                                            .font(.subheadline.weight(.bold))

                                        Text("SHA-256: \(group.hashHex)…")
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 7)
                                            .padding(.vertical, 2)
                                            .background(Color.teal.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.teal)

                                        Spacer()

                                        Text("Economia: \(ByteFormatter.string(from: group.selectedReclaimableBytes))")
                                            .font(.system(.caption, design: .monospaced).weight(.bold))
                                            .foregroundStyle(.teal)
                                    }

                                    Divider()

                                    ForEach(Array(group.files.enumerated()), id: \.element.id) { fileIdx, file in
                                        HStack(spacing: 10) {
                                            Toggle("", isOn: Binding(
                                                get: { file.isSelectedForRemoval },
                                                set: { val in
                                                    scanner.duplicateGroups[groupIdx].files[fileIdx].isSelectedForRemoval = val
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
                SafetyNoticePill(text: "Pelo menos 1 cópia original é sempre preservada. As cópias marcadas vão para a Lixeira primeiro.")
                Spacer()
                Button {
                    Task { _ = await scanner.cleanSelectedDuplicates() }
                } label: {
                    Label(
                        "Remover Cópias Duplicadas (\(ByteFormatter.string(from: scanner.selectedDuplicatesReclaimableBytes)))",
                        systemImage: "trash"
                    )
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(scanner.selectedDuplicatesReclaimableBytes == 0 || scanner.isScanningDuplicates)
            }
        }
        .padding(24)
        .task {
            if scanner.duplicateGroups.isEmpty && !scanner.isScanningDuplicates {
                await scanner.scanDuplicateFiles()
            }
        }
    }
}
