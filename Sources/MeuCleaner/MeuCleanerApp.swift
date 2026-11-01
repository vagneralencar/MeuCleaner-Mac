import SwiftUI
import AppKit

@main
public struct MeuCleanerApp: App {
    @StateObject private var scanner = DiskScannerService()
    @StateObject private var monitor = SystemMonitorService()
    @StateObject private var updater = SelfUpdaterService()
    @State private var selectedChannel: CleanerChannel = .home

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public var body: some Scene {
        WindowGroup("MeuCleaner", id: "main") {
            MainView(
                scanner: scanner,
                monitor: monitor,
                updater: updater,
                selectedChannel: $selectedChannel
            )
            .frame(minWidth: 980, minHeight: 660)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandMenu("Navegar") {
                ForEach(CleanerChannel.allCases) { channel in
                    Button(channel.title) {
                        selectedChannel = channel
                    }
                    .keyboardShortcut(channel.shortcutKey, modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView(scanner: scanner, updater: updater)
        }

        MenuBarExtra {
            MenuBarPopoverView(monitor: monitor, scanner: scanner, updater: updater)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                Text("\(Int(monitor.cpuUsagePercent))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
        }
        .menuBarExtraStyle(.window)
    }
}
