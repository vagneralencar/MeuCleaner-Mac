import SwiftUI

public struct SystemJunkChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var selectedCategory: JunkCategory? = nil

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
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
                    "Nem um farelo de pão de queijo.",
                    systemImage: "sparkles",
                    description: Text("Nenhum cache, log ou download pela metade sobrando no seu Mac.")
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
                                                scanner.junkItems[idx].isSelected = newValue
                                            }
                                        }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()

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

                                    Text(ByteFormatter.string(from: item.sizeBytes))
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

            // Bottom Action Bar with Removal Mode Picker
            HStack(spacing: 14) {
                Picker("Destino:", selection: $scanner.removalMode) {
                    ForEach(RemovalMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)

                Text(scanner.removalMode.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                if scanner.removalMode == .trash {
                    Button {
                        Task {
                            _ = await scanner.cleanSelectedJunk()
                        }
                    } label: {
                        Label(
                            "Limpar (\(ByteFormatter.string(from: scanner.selectedJunkBytes)))",
                            systemImage: "trash"
                        )
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(scanner.selectedJunkBytes == 0 || scanner.isScanningJunk)
                } else {
                    HoldToConfirmButton(
                        title: "Segure p/ Apagar (\(ByteFormatter.string(from: scanner.selectedJunkBytes)))",
                        symbol: "flame.fill",
                        holdDuration: 1.0,
                        isDisabled: scanner.selectedJunkBytes == 0 || scanner.isScanningJunk
                    ) {
                        Task {
                            _ = await scanner.cleanSelectedJunk()
                        }
                    }
                }
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
