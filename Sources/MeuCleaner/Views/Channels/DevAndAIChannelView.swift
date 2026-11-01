import SwiftUI

public struct DevAndAIChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var selectedCategory: DevArtifactCategory = .all

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    private var filteredArtifacts: [DevArtifactItem] {
        guard selectedCategory != .all else { return scanner.devArtifacts }
        return scanner.devArtifacts.filter { $0.category == selectedCategory }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .devAndAI,
                trailingBadgeText: "\(ByteFormatter.string(from: scanner.selectedDevArtifactsBytes)) / \(ByteFormatter.string(from: scanner.totalDevArtifactsBytes))",
                actionTitle: scanner.isScanningDevArtifacts ? "Escaneando Projetos..." : "Escanear Projetos & IA",
                isLoading: scanner.isScanningDevArtifacts,
                onAction: {
                    Task { await scanner.scanDevAndAIArtifacts() }
                }
            )

            // Filter Pills + Xcode Simulators Purge Action
            HStack(spacing: 10) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(DevArtifactCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.symbol)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedCategory == category ? Color.mint : Color.primary.opacity(0.07),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedCategory == category ? .black : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await scanner.inspectXcodeSimulators() }
                } label: {
                    Label("Analisar Simuladores", systemImage: "iphone.slash")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .tint(.mint)
                .controlSize(.small)
                .help("Analisa o espaço dos simuladores sem apagar dados de testes")
            }

            if scanner.isScanningDevArtifacts {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Analisando node_modules, .venv, target, .build e modelos Ollama/HuggingFace...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if filteredArtifacts.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nenhum artefato pesado encontrado",
                    systemImage: "cpu",
                    description: Text("Seus diretórios de código (~/dev, ~/Developer, ~/Projects) e caches de IA estão enxutos.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredArtifacts) { item in
                            GlassCard(padding: 12, cornerRadius: 12) {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { item.isSelected },
                                        set: { val in
                                            if let idx = scanner.devArtifacts.firstIndex(where: { $0.id == item.id }) {
                                                scanner.devArtifacts[idx].isSelected = val
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .disabled((try? SafetyGuard.validateCanMoveToTrash(item.url)) == nil)
                                    .help("Projetos e worktrees são preservados, inclusive arquivos ignorados.")

                                    Image(systemName: item.category.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.mint)
                                        .frame(width: 32, height: 32)
                                        .background(Color.mint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(item.projectName + ((try? SafetyGuard.validateCanMoveToTrash(item.url)) == nil ? " · Preservado" : ""))
                                                .font(.subheadline.weight(.bold))

                                            Text(item.artifactFolderName)
                                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2)
                                                .background(Color.mint.opacity(0.16), in: Capsule())
                                                .foregroundStyle(.mint)

                                            if item.daysInactive >= 30 {
                                                Text("Inativo há \(item.daysInactive)d")
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(Color.orange.opacity(0.18), in: Capsule())
                                                    .foregroundStyle(.orange)
                                            }
                                        }

                                        Text(item.url.path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(ByteFormatter.string(from: item.sizeBytes))
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))

                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .help("Mostrar no Finder")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            HStack {
                SafetyNoticePill(text: "Seu código-fonte nunca é tocado: apenas pastas de dependências/build regeneráveis ou modelos selecionados vão para a Lixeira.")
                Spacer()
                Button {
                    Task { _ = await scanner.cleanSelectedDevArtifacts() }
                } label: {
                    Label(
                        "Revisar artefatos (\(ByteFormatter.string(from: scanner.selectedDevArtifactsBytes)))",
                        systemImage: "trash"
                    )
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.mint)
                .disabled(scanner.selectedDevArtifactsBytes == 0 || scanner.isScanningDevArtifacts)
            }
        }
        .padding(24)
        .task {
            if scanner.devArtifacts.isEmpty && !scanner.isScanningDevArtifacts {
                await scanner.scanDevAndAIArtifacts()
            }
        }
    }
}
