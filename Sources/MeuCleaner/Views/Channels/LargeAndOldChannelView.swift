import SwiftUI

public struct LargeAndOldChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var selectedCategory: LargeFileCategory = .all
    @State private var selectedAge: FileAgeFilter = .any
    @State private var sortByOldestFirst: Bool = false

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    private var filteredFiles: [LargeFileItem] {
        let filtered = scanner.largeFiles.filter { item in
            let matchesType = (selectedCategory == .all) || (item.category == selectedCategory)
            let matchesAge = item.daysSinceAccess >= selectedAge.minimumDays
            return matchesType && matchesAge
        }
        if sortByOldestFirst {
            return filtered.sorted { $0.lastAccessed < $1.lastAccessed }
        } else {
            return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .largeAndOld,
                trailingBadgeText: ByteFormatter.string(from: scanner.selectedLargeFilesBytes),
                actionTitle: scanner.isScanningLargeFiles ? "Buscando..." : "Reescanear Arquivos",
                isLoading: scanner.isScanningLargeFiles,
                onAction: {
                    Task { await scanner.scanLargeAndOldFiles() }
                }
            )

            // Type & Age Filter Bar
            HStack(spacing: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(LargeFileCategory.allCases) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Label(category.rawValue, systemImage: category.symbol)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(
                                        selectedCategory == category ? Color.purple : Color.primary.opacity(0.07),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(selectedCategory == category ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()

                Picker("Idade:", selection: $selectedAge) {
                    ForEach(FileAgeFilter.allCases) { age in
                        Text(age.rawValue).tag(age)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 155)

                Toggle("Mais antigos primeiro", isOn: $sortByOldestFirst)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.caption)
            }

            if scanner.isScanningLargeFiles {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Procurando arquivos grandes em Downloads, Filmes, Música e Developer...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if filteredFiles.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nenhum arquivo grande para este filtro",
                    systemImage: "doc.badge.clock",
                    description: Text("Experimente mudar o filtro de tipo ou idade acima.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredFiles) { file in
                            GlassCard(padding: 12, cornerRadius: 12) {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { file.isSelected },
                                        set: { val in
                                            if let idx = scanner.largeFiles.firstIndex(where: { $0.id == file.id }) {
                                                scanner.largeFiles[idx].isSelected = val
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()

                                    Image(systemName: file.category.symbol)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.purple)
                                        .frame(width: 32, height: 32)
                                        .background(Color.purple.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(file.name)
                                            .font(.subheadline.weight(.semibold))
                                            .lineLimit(1)
                                        Text(file.url.path)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    Text(file.daysSinceAccess == 0 ? "Aberto hoje" : "Há \(file.daysSinceAccess) dias")
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.primary.opacity(0.06), in: Capsule())
                                        .foregroundStyle(.secondary)

                                    Text(ByteFormatter.string(from: file.sizeBytes))
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .frame(width: 90, alignment: .trailing)

                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
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
                SafetyNoticePill(text: "Nada vem marcado por padrão. Revise e envie o que não precisa mais para a Lixeira.")
                Spacer()
                Button {
                    Task {
                        _ = await scanner.cleanSelectedLargeFiles()
                    }
                } label: {
                    Label(
                        "Mover para a Lixeira (\(ByteFormatter.string(from: scanner.selectedLargeFilesBytes)))",
                        systemImage: "trash"
                    )
                    .fontWeight(.semibold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(scanner.selectedLargeFilesBytes == 0)
            }
        }
        .padding(24)
        .task {
            if scanner.largeFiles.isEmpty && !scanner.isScanningLargeFiles {
                await scanner.scanLargeAndOldFiles()
            }
        }
    }
}
