import SwiftUI

struct OverviewView: View {
    @ObservedObject var library: PageLibrary
    var onOpen: (String) -> Void
    var onTrash: (String) -> Void
    var onRestore: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("继续书写") {
                    ForEach(library.live, id: \.id) { p in
                        Button { onOpen(p.id); dismiss() } label: { row(p, current: p.id == library.currentID) }
                            .swipeActions {
                                Button(role: .destructive) { onTrash(p.id) } label: {
                                    Label("移到废纸篓", systemImage: "trash")
                                }
                            }
                    }
                }
                if !library.trash.isEmpty {
                    Section("废纸篓") {
                        ForEach(library.trash, id: \.id) { p in
                            Button { onRestore(p.id) } label: { row(p, current: false) }
                                .swipeActions {
                                    Button { onRestore(p.id) } label: {
                                        Label("恢复", systemImage: "arrow.uturn.backward")
                                    }.tint(.blue)
                                }
                        }
                    }
                }
            }
            .navigationTitle("纸页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("完成") { dismiss() } }
        }
    }

    private func row(_ p: PageInfo, current: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(p.summary.isEmpty ? "空白的一页" : p.summary)
                    .foregroundStyle(p.summary.isEmpty ? .secondary : .primary)
                    .lineLimit(1)
                // 空页没有修改时间,不画这一行。
                if let ms = p.modifiedMs {
                    Text(Date(timeIntervalSince1970: Double(ms) / 1000)
                        .formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if current { Image(systemName: "pencil").foregroundStyle(.secondary) }
        }
    }
}
