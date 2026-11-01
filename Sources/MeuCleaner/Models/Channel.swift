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
    case devAndAI = 8
    case startupItems = 9
    case duplicates = 10
    case developerStorage = 11
    case history = 12

    static let primary: [CleanerChannel] = [.home, .developerStorage, .history]
    static let explorers: [CleanerChannel] = [.spaceLens, .duplicates, .largeAndOld]
    static var tools: [CleanerChannel] { allCases.filter { !primary.contains($0) && $0 != .systemJunk } }
    static var otherTools: [CleanerChannel] { tools.filter { !explorers.contains($0) } }

    public var id: Int { rawValue }

    public var code: String {
        String(format: "%02d", rawValue)
    }

    public var title: String {
        switch self {
        case .home: return "Visão geral"
        case .systemJunk: return "Lixo do Sistema"
        case .spaceLens: return "Space Lens"
        case .largeAndOld: return "Grandes e Antigos"
        case .uninstaller: return "Desinstalador"
        case .leftovers: return "Restos de Apps"
        case .trash: return "Lixeira"
        case .appUpdater: return "Atualizador de Apps"
        case .devAndAI: return "Dev & IA Cleaner"
        case .startupItems: return "Inicialização & Daemons"
        case .duplicates: return "Arquivos Duplicados"
        case .developerStorage: return "Revisar limpeza"
        case .history: return "Histórico"
        }
    }

    public var subtitle: String {
        switch self {
        case .home: return "Entenda o espaço do seu Mac e decida o que revisar"
        case .systemJunk: return "Caches de apps, logs, Xcode DerivedData, npm, pnpm, bun, Cargo e Gradle"
        case .spaceLens: return "Mapa visual do seu disco em anéis interativos por nível de pasta"
        case .largeAndOld: return "Arquivos enormes e esquecidos filtrados por tipo e idade"
        case .uninstaller: return "Desinstale apps junto com tudo na Library (suporta Drag & Drop de .app)"
        case .leftovers: return "Arquivos órfãos na Library deixados por apps que você já apagou"
        case .trash: return "Veja o que pesa na Lixeira do macOS e esvazie com segurança"
        case .appUpdater: return "Atualizações em 1 clique via Homebrew, Sparkle e App Store"
        case .devAndAI: return "node_modules, .venv, target/build de projetos inativos e modelos de IA (Ollama/HF)"
        case .startupItems: return "Gerencie LaunchAgents e Daemons ocultos que iniciam junto com o Mac"
        case .duplicates: return "Compare arquivos idênticos e escolha quais cópias manter"
        case .developerStorage: return "Escolha o que remover e entenda o que será preservado"
        case .history: return "Acompanhe o crescimento, os resultados e as opções de restauração"
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
        case .devAndAI: return "cpu.fill"
        case .startupItems: return "bolt.horizontal.circle.fill"
        case .duplicates: return "doc.on.doc.fill"
        case .developerStorage: return "checklist"
        case .history: return "clock.arrow.circlepath"
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
        case .devAndAI: return .mint
        case .startupItems: return .yellow
        case .duplicates: return .teal
        case .developerStorage: return .cyan
        case .history: return .blue
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
        case .devAndAI: return "8"
        case .startupItems: return "9"
        case .duplicates: return "d"
        case .developerStorage: return "e"
        case .history: return "h"
        }
    }

    public var isProDifferentiator: Bool {
        switch self {
        case .devAndAI, .startupItems, .duplicates:
            return true
        default:
            return false
        }
    }
}
