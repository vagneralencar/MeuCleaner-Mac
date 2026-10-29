import SwiftUI

public struct RingSegment: Identifiable {
    public let id: UUID
    public let node: DiskNode
    public let ringLevel: Int // 1 or 2
    public let startAngle: Angle
    public let endAngle: Angle
    public let color: Color
}

public struct SpaceLensRingChart: View {
    public let rootNode: DiskNode
    @Binding public var hoveredNode: DiskNode?
    public let onSelectNode: (DiskNode) -> Void

    private static let palette: [Color] = [
        .cyan, .blue, .indigo, .purple, .pink, .orange, .mint, .teal
    ]

    public init(
        rootNode: DiskNode,
        hoveredNode: Binding<DiskNode?>,
        onSelectNode: @escaping (DiskNode) -> Void
    ) {
        self.rootNode = rootNode
        self._hoveredNode = hoveredNode
        self.onSelectNode = onSelectNode
    }

    private var segments: [RingSegment] {
        guard rootNode.sizeBytes > 0 else { return [] }
        var result: [RingSegment] = []
        let total = Double(rootNode.sizeBytes)
        var currentDeg: Double = -90.0

        for (index, child) in rootNode.children.prefix(10).enumerated() {
            let fraction = max(0.015, Double(child.sizeBytes) / total)
            let sweep = fraction * 360.0
            let start = currentDeg
            let end = currentDeg + max(2.0, sweep - 1.8) // small gap between arcs
            let baseColor = Self.palette[index % Self.palette.count]

            result.append(
                RingSegment(
                    id: child.id,
                    node: child,
                    ringLevel: 1,
                    startAngle: .degrees(start),
                    endAngle: .degrees(end),
                    color: baseColor
                )
            )

            // Outer ring (level 2 children)
            if !child.children.isEmpty && child.sizeBytes > 0 {
                var subDeg = start
                let subTotal = Double(child.sizeBytes)
                for subChild in child.children.prefix(5) {
                    let subFraction = Double(subChild.sizeBytes) / subTotal
                    let subSweep = subFraction * (end - start)
                    if subSweep >= 3.0 {
                        result.append(
                            RingSegment(
                                id: subChild.id,
                                node: subChild,
                                ringLevel: 2,
                                startAngle: .degrees(subDeg),
                                endAngle: .degrees(subDeg + max(1.5, subSweep - 1.2)),
                                color: baseColor.opacity(0.68)
                            )
                        )
                    }
                    subDeg += subSweep
                }
            }

            currentDeg += sweep
        }

        return result
    }

    public var body: some View {
        ZStack {
            // Subtle background tracks
            Circle()
                .stroke(Color.primary.opacity(0.06), lineWidth: 32)
                .frame(width: 210, height: 210)

            Circle()
                .stroke(Color.primary.opacity(0.04), lineWidth: 24)
                .frame(width: 282, height: 282)

            ForEach(segments) { seg in
                let isHovered = hoveredNode?.id == seg.node.id
                let diameter: CGFloat = seg.ringLevel == 1 ? 210 : 282
                let lineWidth: CGFloat = seg.ringLevel == 1 ? (isHovered ? 36 : 32) : (isHovered ? 28 : 24)

                RingArcShape(startAngle: seg.startAngle, endAngle: seg.endAngle)
                    .stroke(
                        seg.color.opacity(isHovered ? 1.0 : 0.85),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                    )
                    .frame(width: diameter, height: diameter)
                    .shadow(color: isHovered ? seg.color.opacity(0.45) : .clear, radius: 8)
                    .onHover { hovering in
                        withAnimation(.easeInOut(duration: 0.12)) {
                            if hovering {
                                hoveredNode = seg.node
                            } else if hoveredNode?.id == seg.node.id {
                                hoveredNode = nil
                            }
                        }
                    }
                    .onTapGesture {
                        onSelectNode(seg.node)
                    }
            }

            // Center Hub Info
            VStack(spacing: 4) {
                if let hovered = hoveredNode {
                    Image(systemName: hovered.isDirectory ? "folder.fill" : "doc.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.cyan)
                    Text(hovered.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: 130)
                    Text(ByteFormatter.string(from: hovered.sizeBytes))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    if hovered.isDirectory {
                        Text("Clique para abrir")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("MAPEADO")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(ByteFormatter.string(from: rootNode.sizeBytes))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    Text(rootNode.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 130)
                }
            }
        }
        .frame(width: 330, height: 330)
    }
}

private struct RingArcShape: Shape {
    let startAngle: Angle
    let endAngle: Angle

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2.0
        path.addArc(
            center: center,
            radius: radius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        return path
    }
}
