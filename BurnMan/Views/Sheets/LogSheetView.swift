import SwiftUI

struct LogSheetView: View {
    let title: String
    let log: [String]
    @Environment(\.dismiss) private var dismiss

    private var fullLogText: String {
        log.joined(separator: "\n")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(log.indices, id: \.self) { index in
                        let line = log[index]
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.contains("ERREUR") || line.contains("ERROR") ? .red : .primary)
                            .textSelection(.enabled)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(fullLogText, forType: .string)
                    } label: {
                        Label("Copier tout", systemImage: "doc.on.doc")
                    }
                    .help("Copier tout le log")
                    .disabled(log.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
            .contextMenu {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullLogText, forType: .string)
                } label: {
                    Label("Copier tout", systemImage: "doc.on.doc")
                }
                .disabled(log.isEmpty)
            }
        }
        .frame(width: 600, height: 400)
    }
}
