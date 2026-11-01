import SwiftUI

struct DashboardMetrics: View {
    @ObservedObject var monitor: SystemMonitorService

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Seu Mac agora").font(.headline)
                Spacer()
                Text("Somente informação · atualiza a cada 3 s").font(.caption).foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                metric("Processador", value: monitor.hasCPUSample ? String(format: "%.0f%%", monitor.cpuUsagePercent) : "Medindo…",
                       detail: "Uso da CPU", symbol: "cpu.fill", color: .blue)
                metric("Memória", value: ByteCountFormatter.string(fromByteCount: monitor.memoryUsedBytes, countStyle: .memory),
                       detail: "de \(ByteCountFormatter.string(fromByteCount: monitor.memoryTotalBytes, countStyle: .memory)) de RAM", symbol: "memorychip.fill", color: .purple)
                metric("Rede", value: "↓ \(ByteFormatter.string(from: monitor.networkDownBytesPerSec))/s",
                       detail: "↑ \(ByteFormatter.string(from: monitor.networkUpBytesPerSec))/s", symbol: "network", color: .cyan)
                metric("Energia", value: monitor.hasBattery ? "\(monitor.batteryPercent)%" : "Na tomada",
                       detail: monitor.hasBattery ? (monitor.isCharging ? "Conectado à energia" : "Usando a bateria") : "Sem bateria interna",
                       symbol: monitor.hasBattery ? (monitor.isCharging ? "battery.100.bolt" : "battery.100") : "powerplug.fill", color: .green)
            }
        }
    }

    private func metric(_ title: String, value: String, detail: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(color.opacity(0.18), lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

struct DashboardTools: View {
    @Binding var selectedChannel: CleanerChannel
    private let featured: [CleanerChannel] = [.spaceLens, .duplicates, .largeAndOld, .uninstaller, .leftovers, .trash]
    private let columns = [GridItem(.adaptive(minimum: 260), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Explore seus arquivos").font(.title2.bold())
            Text("Veja o que ocupa espaço e compare arquivos. Abrir uma ferramenta não apaga nada.")
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(featured) { tool in shortcut(tool) }
            }
            DisclosureGroup("Mais ferramentas · atualizações, desenvolvimento e inicialização") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(CleanerChannel.tools.filter { !featured.contains($0) }) { tool in shortcut(tool) }
                }.padding(.top, 12)
            }.font(.callout)
        }
    }

    private func shortcut(_ channel: CleanerChannel) -> some View {
        Button { selectedChannel = channel } label: {
            HStack(spacing: 12) {
                Image(systemName: channel.symbol).font(.title2)
                    .foregroundStyle(channel.accentColor).frame(width: 42, height: 42)
                    .background(channel.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title).font(.headline).foregroundStyle(.primary)
                    Text(description(channel)).font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(channel.accentColor)
            }.frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(14)
                .background(channel.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(channel.accentColor.opacity(0.16), lineWidth: 1))
                .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
    }

    private func description(_ channel: CleanerChannel) -> String {
        switch channel {
        case .spaceLens: return "Mapa visual para explorar pastas e tamanhos"
        case .duplicates: return "Compare cópias e escolha quais manter"
        case .largeAndOld: return "Encontre arquivos por tamanho e idade"
        case .uninstaller: return "Revise apps e seus arquivos relacionados"
        case .trash: return "Confira os itens que já estão na Lixeira"
        case .leftovers: return "Revise arquivos deixados por aplicativos"
        case .appUpdater: return "Consulte atualizações dos seus aplicativos"
        case .devAndAI: return "Explore arquivos de desenvolvimento e modelos"
        case .startupItems: return "Veja os serviços iniciados com o Mac"
        default: return channel.subtitle
        }
    }
}
