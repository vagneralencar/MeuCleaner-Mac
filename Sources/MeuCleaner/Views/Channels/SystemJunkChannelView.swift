import SwiftUI

public struct SystemJunkChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var selectedCategory: JunkCategory? = nil

    private let openEnvironments: () -> Void
    public init(scanner: DiskScannerService, openEnvironments: @escaping () -> Void = {}) {
        self.scanner = scanner
        self.openEnvironments = openEnvironments
    }

    private var filteredItems: [JunkItem] {
        guard let cat = selectedCategory else { return scanner.junkItems }
        return scanner.junkItems.filter { $0.category == cat }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .systemJunk,
                trailingBadgeText: "\(ByteFormatter.string(from: scanner.selectedJunkBytes)) / \(ByteFormatter.string(from: scanner.totalJunkBytes))",
                actionTitle: scanner.isScanningJunk ? "Escaneando..." : "Escanear de novo",
                isLoading: scanner.isScanningJunk,
                onAction: {
                    Task { await scanner.scanSystemJunk() }
                }
            )

            Text("Tamanhos medidos, não espaço garantido. * Cópias APFS podem compartilhar blocos. Itens em uso ou não verificados ficam bloqueados.")
                .font(.caption).foregroundStyle(.secondary)

            Button("Revisar por categoria: Chrome, Docker, Xcode e Android", action: openEnvironments)
                .buttonStyle(.bordered)

            // Category Filter Pills
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryFilterButton(
                        title: "Todas as Categorias",
                        symbol: "square.grid.2x2.fill",
                        sizeText: ByteFormatter.string(from: scanner.totalJunkBytes),
                        isSelected: selectedCategory == nil
                    ) {
                        selectedCategory = nil
                    }

                    ForEach(JunkCategory.allCases) { category in
                        let catBytes = scanner.junkItems
                            .filter { $0.category == category }
                            .reduce(0) { $0 + $1.sizeBytes }
                        if catBytes > 0 {
                            CategoryFilterButton(
                                title: category.rawValue,
                                symbol: category.symbol,
                                sizeText: ByteFormatter.string(from: catBytes),
                                isSelected: selectedCategory == category
                            ) {
                                selectedCategory = category
                            }
                        }
                    }
                }
            }

            if scanner.isScanningJunk {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Analisando caches, logs, Xcode, ~/.cache e pacotes de desenvolvimento...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if filteredItems.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "Nenhum item nesta lista",
                    systemImage: "sparkles",
                    description: Text("Consulte Docker e SDKs e os avisos da análise. Uma lista vazia não significa que todos os locais foram verificados.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredItems) { item in
                            GlassCard(padding: 12, cornerRadius: 12) {
                                HStack(spacing: 12) {
                                    Toggle("", isOn: Binding(
                                        get: { item.isSelected },
                                        set: { newValue in
                                            if let idx = scanner.junkItems.firstIndex(where: { $0.id == item.id }) {
                                                scanner.junkItems[idx].isSelected = newValue && item.canClean
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    .disabled(!item.canClean || scanner.isCleaningJunk)

                                    Image(systemName: item.category.symbol)
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundStyle(.orange)
                                        .frame(width: 30, height: 30)
                                        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 8) {
                                            Text(item.name)
                                                .font(.subheadline.weight(.semibold))
                                            if let note = item.note {
                                                Text(note)
                                                    .font(.system(size: 10, weight: .semibold))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 2)
                                                    .background(.yellow.opacity(0.2), in: Capsule())
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

                                    Text(ByteFormatter.string(from: item.sizeBytes) + (item.sharedBlocks ? " *" : ""))
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))

                                    Button {
                                        NSWorkspace.shared.activateFileViewerSelecting([item.url])
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.caption)
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
                Text("Revise o destino e o motivo de cada item antes de limpar.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Revisar seleção") {
                    let paths = Set(scanner.junkItems.filter { $0.isSelected && $0.canClean }.map { $0.url.path })
                    scanner.review(scanner.storageReport.findings.filter { paths.contains($0.id) }, title: "Arquivos e caches")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!scanner.junkItems.contains { $0.isSelected && $0.canClean } || scanner.isScanningJunk || scanner.isCleaningJunk)
            }
        }
        .padding(24)
        .task {
            if scanner.junkItems.isEmpty && !scanner.isScanningJunk {
                await scanner.scanSystemJunk()
            }
        }
    }
}

private struct CategoryFilterButton: View {
    let title: String
    let symbol: String
    let sizeText: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(sizeText)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .opacity(0.85)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.orange : Color.primary.opacity(0.07),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
