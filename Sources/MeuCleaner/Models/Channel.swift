import SwiftUI

public enum CleanerChannel: Int, CaseIterable, Identifiable, Hashable {
    case home = 0
    case systemJunk = 1
    case spaceLens = 2
    case largeAndOld = 3
    case uninstaller = 4
    case leftovers = 5
    case trash = 6
    case appUpdater = 7

    public var id: Int { rawValue }

    public var code: String {
        String(format: "%02d", rawValue)
    }

    public var title: String {
        switch self {
        case .home: return "Varredura Inteligente"
        case .systemJunk: return "Lixo do Sistema"
        case .spaceLens: return "Space Lens"
        case .largeAndOld: return "Grandes e Antigos"
        case .uninstaller: return "Desinstalador"
        case .leftovers: return "Restos de Apps"
        case .trash: return "Lixeira"
        case .appUpdater: return "Atualizador de Apps"
        }
    }

    public var subtitle: String {
        switch self {
        case .home: return "Resumo rápido do seu Mac, lixo seguro para limpar e espaço livre"
        case .systemJunk: return "Caches de apps, logs, Xcode DerivedData, npm, pnpm, bun, Cargo e Gradle"
        case .spaceLens: return "Mapa visual do seu disco em anéis interativos por nível de pasta"
        case .largeAndOld: return "Arquivos enormes e esquecidos filtrados por tipo e idade"
        case .uninstaller: return "Desinstale aplicativos junto com tudo o que espalharam na Library"
        case .leftovers: return "Arquivos órfãos na Library deixados por apps que você já apagou"
        case .trash: return "Veja o que pesa na Lixeira do macOS e esvazie com segurança"
        case .appUpdater: return "Atualizações via Homebrew e Sparkle em um só lugar"
        }
    }

    public var symbol: String {
        switch self {
        case .home: return "sparkles"
        case .systemJunk: return "internaldrive.trianglebadge.exclamationmark"
        case .spaceLens: return "circle.hexagongrid.fill"
        case .largeAndOld: return "doc.badge.clock"
        case .uninstaller: return "square.stack.3d.up.slash.fill"
        case .leftovers: return "puzzlepiece.extension.fill"
        case .trash: return "trash.fill"
        case .appUpdater: return "arrow.triangle.2.circlepath.circle.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .home: return .blue
        case .systemJunk: return .orange
        case .spaceLens: return .cyan
        case .largeAndOld: return .purple
        case .uninstaller: return .red
        case .leftovers: return .indigo
        case .trash: return .pink
        case .appUpdater: return .green
        }
    }

    public var shortcutKey: KeyEquivalent {
        switch self {
        case .home: return "0"
        case .systemJunk: return "1"
        case .spaceLens: return "2"
        case .largeAndOld: return "3"
        case .uninstaller: return "4"
        case .leftovers: return "5"
        case .trash: return "6"
        case .appUpdater: return "7"
        }
    }
}
