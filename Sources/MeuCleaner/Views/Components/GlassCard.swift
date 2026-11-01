import SwiftUI

public struct GlassCard<Content: View>: View {
    private let material: Material
    private let padding: CGFloat
    private let cornerRadius: CGFloat
    private let content: Content

    public init(
        material: Material = .regularMaterial,
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 16,
        @ViewBuilder content: () -> Content
    ) {
        self.material = material
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(material)
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.primary.opacity(0.16),
                                Color.primary.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
    }
}

public struct ChannelHeaderView: View {
    public let channel: CleanerChannel
    public let trailingBadgeText: String?
    public let actionTitle: String?
    public let isLoading: Bool
    public let onAction: (() -> Void)?

    public init(
        channel: CleanerChannel,
        trailingBadgeText: String? = nil,
        actionTitle: String? = nil,
        isLoading: Bool = false,
        onAction: (() -> Void)? = nil
    ) {
        self.channel = channel
        self.trailingBadgeText = trailingBadgeText
        self.actionTitle = actionTitle
        self.isLoading = isLoading
        self.onAction = onAction
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                channel.accentColor.opacity(0.25),
                                channel.accentColor.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(channel.accentColor.opacity(0.35), lineWidth: 1)
                    )

                Image(systemName: channel.symbol)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(channel.accentColor)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(channel.title)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }

                Text(channel.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if let badge = trailingBadgeText {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("MEDIÇÃO")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(badge)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(channel.accentColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let actionTitle, let onAction {
                Button(action: onAction) {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(actionTitle)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(channel.accentColor)
                .disabled(isLoading)
            }
        }
        .padding(.bottom, 4)
    }
}

public struct SafetyNoticePill: View {
    public let text: String

    public init(text: String = "Revise os itens e o destino antes de confirmar. A Lixeira é a opção padrão.") {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(.green)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
