import SwiftUI

/// A safety button inspired by CleanUai where permanent deletion only happens by holding the button
/// until the progress meter fills up (1.5 seconds). A stray click deletes nothing.
public struct HoldToConfirmButton: View {
    public let title: String
    public let symbol: String
    public let holdDuration: Double
    public let isDisabled: Bool
    public let onConfirmed: () -> Void

    @State private var isPressing: Bool = false
    @State private var progress: CGFloat = 0.0
    @State private var holdTimer: Timer?
    @State private var showingAccessibleConfirmation = false

    public init(
        title: String,
        symbol: String = "trash.slash.fill",
        holdDuration: Double = 1.4,
        isDisabled: Bool = false,
        onConfirmed: @escaping () -> Void
    ) {
        self.title = title
        self.symbol = symbol
        self.holdDuration = holdDuration
        self.isDisabled = isDisabled
        self.onConfirmed = onConfirmed
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isDisabled ? Color.gray.opacity(0.18) : Color.red.opacity(0.18))

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.red, .orange],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * progress)
                    .animation(.linear(duration: 0.05), value: progress)
            }

            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .bold))
                Text(isPressing ? "Segure para confirmar (\(Int(progress * 100))%)..." : title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(isPressing ? .white : (isDisabled ? .secondary : .red))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
        }
        .frame(width: 260, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isDisabled ? Color.gray.opacity(0.25) : Color.red.opacity(0.45), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isDisabled, !isPressing else { return }
                    startHold()
                }
                .onEnded { _ in
                    cancelHold()
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint("Abre uma confirmação de exclusão permanente")
        .accessibilityAction {
            if !isDisabled {
                showingAccessibleConfirmation = true
            }
        }
        .disabled(isDisabled)
        .alert("Confirmar exclusão permanente", isPresented: $showingAccessibleConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Apagar permanentemente", role: .destructive) {
                if !isDisabled { onConfirmed() }
            }
        } message: {
            Text("\(title). Esta ação não pode ser desfeita.")
        }
        .onChange(of: isDisabled) { _, disabled in
            if disabled { cancelHold(); showingAccessibleConfirmation = false }
        }
        .onDisappear { cancelHold(); showingAccessibleConfirmation = false }
    }

    private func startHold() {
        isPressing = true
        progress = 0.0
        let interval = 0.03
        let step = CGFloat(interval / holdDuration)

        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { timer in
            Task { @MainActor in
                guard isPressing, !isDisabled else { timer.invalidate(); return }
                progress += step
                if progress >= 1.0 {
                    timer.invalidate()
                    holdTimer = nil
                    isPressing = false
                    progress = 0.0
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    onConfirmed()
                }
            }
        }
    }

    private func cancelHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        isPressing = false
        withAnimation(.easeOut(duration: 0.2)) {
            progress = 0.0
        }
    }
}
