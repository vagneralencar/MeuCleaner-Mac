import SwiftUI

struct CleanupHistoryView: View {
    @ObservedObject var scanner: DiskScannerService
    @Binding var selectedChannel: CleanerChannel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ChannelHeaderView(channel: .history)
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("O que cresceu").font(.title2.bold())
                        if let date = scanner.previousScanDate {
                            Text("Comparado com \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            if scanner.storageGrowth.isEmpty { Text("Nenhum crescimento nos locais comparáveis.") }
                            ForEach(scanner.storageGrowth.prefix(12)) { item in
                                HStack { Text(item.title); Spacer(); Text("+\(ByteFormatter.string(from: item.delta))").monospacedDigit() }
                            }
                        } else {
                            Text("Faça duas análises para comparar os locais lidos por completo.").foregroundStyle(.secondary)
                        }
                        Text("Crescimento não significa lixo. Locais novos, parciais e cópias compartilhadas não entram na comparação.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if scanner.canUndoLastCleanup {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recibos de restauração disponíveis").font(.headline)
                            Text("\(scanner.lastTrashReceipts.count) itens da última operação continuam registrados para restauração. Arquivos existentes não serão sobrescritos.")
                                .font(.callout).foregroundStyle(.secondary)
                            Button("Verificar e restaurar última operação") { Task { await scanner.undoLastCleanup() } }
                                .disabled(scanner.isCleaningJunk || scanner.isScanningJunk || scanner.isRestoring)
                            Button("Ver Lixeira") { selectedChannel = .trash }
                        }
                    }
                }
                Text("Resultados das limpezas").font(.title2.bold())
                if scanner.cleanupActivities.isEmpty {
                    Text("As próximas operações aparecerão aqui, com os itens removidos, preservados e as falhas.")
                        .foregroundStyle(.secondary)
                }
                ForEach(scanner.cleanupActivities) { activity in
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(activity.title).font(.headline)
                                Spacer()
                                Text(activity.date, format: .dateTime.day().month().hour().minute()).font(.caption)
                            }
                            Text(activity.destination).font(.callout)
                            Text("\(activity.rows.filter(\.success).count) operações confirmadas · \(activity.rows.filter { !$0.success }.count) preservadas ou não confirmadas").font(.caption)
                            if activity.restoredAt != nil { Text("Restauração concluída").font(.caption).foregroundStyle(.green) }
                            Text(activity.note).font(.caption).foregroundStyle(.secondary)
                            DisclosureGroup("Ver resultado por item") {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(activity.rows) { row in
                                        Label(row.title, systemImage: row.success ? "checkmark.circle" : "exclamationmark.circle")
                                        Text(row.message).font(.caption).textSelection(.enabled)
                                    }
                                    Text("Espaço físico livre observado: \(ByteFormatter.string(from: activity.freeBefore)) → \(ByteFormatter.string(from: activity.freeAfter)). A variação pode incluir atividade de outros apps.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                            }
                        }
                    }
                }
                if !scanner.cleanupHistory.isEmpty {
                    DisclosureGroup("Registros resumidos de outras ferramentas") {
                        Text("Estes registros guardam tamanhos processados, não espaço efetivamente liberado. Não têm confirmação do destino ou do resultado por item.").font(.caption)
                        ForEach(scanner.cleanupHistory) { entry in
                            HStack {
                                Text(entry.channelTitle)
                                Spacer()
                                Text("\(entry.itemsCount) itens · \(ByteFormatter.string(from: entry.freedBytes)) processados")
                            }.font(.caption).padding(.vertical, 4)
                        }
                    }
                }
            }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity)
        }
    }
}
