import SwiftUI

public struct SpaceLensChannelView: View {
    @ObservedObject public var scanner: DiskScannerService
    @State private var hoveredNode: DiskNode? = nil

    public init(scanner: DiskScannerService) {
        self.scanner = scanner
    }

    private var currentNode: DiskNode? {
        scanner.spaceLensBreadcrumbs.last ?? scanner.spaceLensRoot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ChannelHeaderView(
                channel: .spaceLens,
                trailingBadgeText: currentNode.map { !$0.isComplete && $0.sizeBytes == 0 ? "Não verificado" : ($0.isComplete ? "" : "Ao menos ") + ByteFormatter.string(from: $0.sizeBytes) },
                actionTitle: scanner.isScanningSpaceLens ? "Mapeando..." : "Remapear Pasta Pessoal",
                isLoading: scanner.isScanningSpaceLens,
                onAction: {
                    Task { await scanner.scanSpaceLens() }
                }
            )

            // Breadcrumb navigation bar + Custom Folder Picker
            HStack(spacing: 8) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(scanner.spaceLensBreadcrumbs.enumerated()), id: \.element.id) { index, crumb in
                            if index > 0 {
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Button {
                                scanner.navigateSpaceLensBreadcrumb(to: index)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: index == 0 ? "house.fill" : "folder.fill")
                                        .font(.caption)
                                    Text(crumb.name)
                                        .font(.caption.weight(.semibold))
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    index == scanner.spaceLensBreadcrumbs.count - 1
                                        ? Color.cyan.opacity(0.2)
                                        : Color.primary.opacity(0.06),
                                    in: Capsule()
                                )
                                .foregroundStyle(index == scanner.spaceLensBreadcrumbs.count - 1 ? .cyan : .primary)
                            }
                            .buttonStyle(.plain)
                            .disabled(scanner.isScanningSpaceLens)
                        }
                    }
                }

                Spacer()

                Button {
                    chooseCustomFolder()
                } label: {
                    Label("Escolher Pasta...", systemImage: "folder.badge.plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(scanner.isScanningSpaceLens)
            }

            if scanner.isScanningSpaceLens {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Construindo anéis de ocupação do disco...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                Spacer()
            } else if let activeNode = currentNode {
                HStack(alignment: .top, spacing: 20) {
                    // Left: Concentric Sunburst Rings
                    GlassCard(padding: 20, cornerRadius: 18) {
                        VStack(spacing: 12) {
                            Text("Mapa de Anéis por Nível de Pasta")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            SpaceLensRingChart(
                                rootNode: activeNode,
                                hoveredNode: $hoveredNode
                            ) { clickedNode in
                                if clickedNode.isDirectory {
                                    Task {
                                        await scanner.drillDownSpaceLens(to: clickedNode)
                                    }
                                }
                            }

                            Text("Passe o mouse sobre os arcos ou clique em uma pasta para mergulhar.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(width: 370)

                    // Right: Navigable Folder & File Breakdown List
                    GlassCard(padding: 16, cornerRadius: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Itens dentro de \"\(activeNode.name)\"")
                                    .font(.headline)
                                Spacer()
                                Text("\(activeNode.children.count) maiores itens")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

                            if activeNode.children.isEmpty {
                                Spacer()
                                ContentUnavailableView(
                                    activeNode.isComplete ? "Pasta verificada vazia" : "Não foi possível verificar esta pasta",
                                    systemImage: "folder",
                                    description: Text("Use a barra de navegação acima para voltar ao nível anterior.")
                                )
                                Spacer()
                            } else {
                                ScrollView {
                                    LazyVStack(spacing: 8) {
                                        ForEach(activeNode.children) { child in
                                            let fraction = activeNode.sizeBytes > 0
                                                ? Double(child.sizeBytes) / Double(activeNode.sizeBytes)
                                                : 0
                                            let isHighlighted = hoveredNode?.id == child.id

                                            HStack(spacing: 12) {
                                                Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                                                    .foregroundStyle(child.isDirectory ? .cyan : .secondary)
                                                    .font(.system(size: 16))
                                                    .frame(width: 24)

                                                VStack(alignment: .leading, spacing: 4) {
                                                    HStack {
                                                        Text(child.name)
                                                            .font(.subheadline.weight(.medium))
                                                            .lineLimit(1)
                                                        Spacer()
                                                        Text(!child.isComplete && child.sizeBytes == 0 ? "Não verificado" : (child.isComplete ? "" : "Ao menos ") + ByteFormatter.string(from: child.sizeBytes))
                                                            .font(.system(.caption, design: .monospaced).weight(.bold))
                                                    }

                                                    GeometryReader { geo in
                                                        ZStack(alignment: .leading) {
                                                            Capsule()
                                                                .fill(Color.primary.opacity(0.08))
                                                            Capsule()
                                                                .fill(
                                                                    LinearGradient(
                                                                        colors: [.cyan, .blue],
                                                                        startPoint: .leading,
                                                                        endPoint: .trailing
                                                                    )
                                                                )
                                                                .frame(width: max(4, geo.size.width * fraction))
                                                        }
                                                    }
                                                    .frame(height: 5)
                                                }

                                                if child.isDirectory {
                                                    Button {
                                                        Task {
                                                            await scanner.drillDownSpaceLens(to: child)
                                                        }
                                                    } label: {
                                                        Image(systemName: "arrow.right.circle")
                                                    }
                                                    .buttonStyle(.borderless)
                                                    .help("Abrir pasta na Space Lens")
                                                }

                                                Button {
                                                    NSWorkspace.shared.activateFileViewerSelecting([child.url])
                                                } label: {
                                                    Image(systemName: "magnifyingglass")
                                                }
                                                .buttonStyle(.borderless)
                                                .help("Mostrar no Finder")


                                            }
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .fill(isHighlighted ? Color.cyan.opacity(0.15) : Color.primary.opacity(0.03))
                                            )
                                            .onHover { hovering in
                                                hoveredNode = hovering ? child : nil
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            if let activeNode = currentNode, !activeNode.isComplete {
                DisclosureGroup("Mapa parcial · alguns locais não puderam ser medidos") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(activeNode.issues, id: \.self) { Text($0).font(.caption) }
                        }
                    }.frame(maxHeight: 120)
                }.foregroundStyle(.orange)
            }
            SafetyNoticePill(text: "Inclui pastas ocultas. Links e outros volumes não são percorridos; vínculos físicos são contados uma vez por nível. Mapa somente de leitura.")
        }
        .padding(24)
        .task {
            if scanner.spaceLensRoot == nil && !scanner.isScanningSpaceLens {
                await scanner.scanSpaceLens()
            }
        }
    }

    private func chooseCustomFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Mapear na Space Lens"
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await scanner.scanSpaceLens(at: url)
            }
        }
    }
}
