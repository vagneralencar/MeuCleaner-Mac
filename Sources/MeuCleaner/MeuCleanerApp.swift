import SwiftUI
import AppKit

@main
public struct MeuCleanerApp: App {
    @StateObject private var scanner = DiskScannerService()
    @StateObject private var monitor = SystemMonitorService()
    @State private var selectedChannel: CleanerChannel = .home

    public init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    public var body: some Scene {
        WindowGroup("MeuCleaner", id: "main") {
            MainView(
                scanner: scanner,
                monitor: monitor,
                selectedChannel: $selectedChannel
            )
            .frame(minWidth: 960, minHeight: 640)
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 740)
        .commands {
            CommandMenu("Canais") {
                ForEach(CleanerChannel.allCases) { channel in
                    Button("\(channel.code) · \(channel.title)") {
                        selectedChannel = channel
                    }
                    .keyboardShortcut(channel.shortcutKey, modifiers: [.command])
                }
            }
        }

        MenuBarExtra {
            MenuBarPopoverView(monitor: monitor, scanner: scanner)
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
