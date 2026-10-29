import SwiftUI

public struct LeftoversChannelView: View {
    @ObservedObject public var scanner: DiskScannerService

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .leftovers,
                trailingBadgeText: "\(ByteFormatter.string(from: scanner.selectedLeftoversBytes)) / \(ByteFormatter.string(from: scanner.totalLeftoversBytes))",
                actionTitle: scanner.isScanningLeftovers ? "Verificando..." : "Reescanear Library",
                isLoading: scanner.isScanningLeftovers,
                onAction: {
                    Task { await scanner.scanAppsAndLeftovers() }
                }
            )

            HStack {
                Text("Nada vem marcado por padrão: revise cada grupo de restos órfãos na Library e escolha o que deseja enviar para a Lixeira.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !scanner.leftoverGroups.isEmpty {
                    Button("Selecionar Tudo") {
                        for idx in scanner.leftoverGroups.indices {
                            scanner.leftoverGroups[idx].isSelected = true
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Limpar Seleção") {
                        for idx in scanner.leftoverGroups.indices {
                            scanner.leftoverGroups[idx].isSelected = false
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if scanner.isScanningLeftovers {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Cruzando pastas de ~/Library com os apps instalados em /Applications...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if scanner.leftoverGroups.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nenhum resto órfão encontrado",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Sua Library não possui pastas órfãs aparentes de aplicativos já removidos.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(scanner.leftoverGroups) { group in
                            GlassCard(padding: 14, cornerRadius: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 12) {
                                        Toggle("", isOn: Binding(
                                            get: { group.isSelected },
                                            set: { newValue in
                                                if let idx = scanner.leftoverGroups.firstIndex(where: { $0.id == group.id }) {
                                                    scanner.leftoverGroups[idx].isSelected = newValue
                                                }
                                            }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()

                                        Image(systemName: "puzzlepiece.extension.fill")
                                            .font(.system(size: 16, weight: .semibold))
                                            .foregroundStyle(.indigo)
                                            .frame(width: 32, height: 32)
                                            .background(Color.indigo.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.inferredAppName)
                                                .font(.subheadline.weight(.bold))
                                            Text("Identificador na Library: \(group.identifierHint)")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }

                                        Spacer()

                                        Text(ByteFormatter.string(from: group.totalSizeBytes))
                                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                            .foregroundStyle(.indigo)
                                    }

                                    ForEach(group.files) { file in
                                        HStack(spacing: 8) {
                                            Text(file.locationType)
                                                .font(.system(size: 10, weight: .semibold))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.indigo.opacity(0.12), in: Capsule())
                                                .foregroundStyle(.indigo)

                                            Text(file.url.path)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                                .truncationMode(.middle)

                                            Spacer()

                                            Button {
                                                NSWorkspace.shared.activateFileViewerSelecting([file.url])
                                            } label: {
                                                Label("Finder", systemImage: "magnifyingglass")
                                                    .font(.caption2)
                                            }
                                            .buttonStyle(.borderless)
                                        }
                                        .padding(.leading, 36)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                SafetyNoticePill(text: "Restos removidos vão para a Lixeira do macOS primeiro, caso você queira restaurar algum.")
                Spacer()
                Button {
                    Task {
                        _ = await scanner.cleanSelectedLeftovers()
                    }
                } label: {
                    Label(
                        "Mover Selecionados para a Lixeira (\(ByteFormatter.string(from: scanner.selectedLeftoversBytes)))",
                        systemImage: "trash"
                    )
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .disabled(scanner.selectedLeftoversBytes == 0)
            }
        }
        .padding(24)
        .task {
            if scanner.leftoverGroups.isEmpty && !scanner.isScanningLeftovers {
                await scanner.scanAppsAndLeftovers()
            }
        }
    }
}
