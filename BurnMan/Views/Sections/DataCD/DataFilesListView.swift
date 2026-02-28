import SwiftUI
import UniformTypeIdentifiers

struct DataFilesListView: View {
    let onOpenFilePicker: () -> Void

    @Environment(DataDiscManager.self) private var dataDiscManager
    @State private var selection: Set<DataFile.ID> = []
    @State private var sortOrder = [KeyPathComparator<DataFile>]()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Files", systemImage: "folder.fill")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if dataDiscManager.files.isEmpty {
                EmptyDropZone(
                    icon: "folder.badge.plus",
                    title: "Add files or folders",
                    subtitle: "Drag and drop files here",
                    onAdd: { onOpenFilePicker() }
                )
            } else {
                VStack(spacing: 0) {
                    filesTable

                    TableBottomBar(
                        onAdd: { onOpenFilePicker() },
                        onRemove: {
                            let offsets = IndexSet(
                                dataDiscManager.files.indices.filter { selection.contains(dataDiscManager.files[$0].id) }
                            )
                            dataDiscManager.removeFiles(at: offsets)
                            selection.removeAll()
                        },
                        removeDisabled: selection.isEmpty
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator)
                )
            }
        }
        .fileDrop { urls in
            dataDiscManager.addFiles(urls: urls)
        }
    }

    // MARK: - Table

    private var filesTable: some View {
        Table(of: DataFile.self, selection: $selection, sortOrder: $sortOrder) {
            columns
        } rows: {
            rows
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 10 * 28)
        .contextMenu(forSelectionType: DataFile.ID.self) { selectedIDs in
            contextMenuItems(for: selectedIDs)
        }
        .onChange(of: sortOrder) { _, newOrder in
            dataDiscManager.sortFiles(using: newOrder)
        }
    }

    // MARK: - Columns

    @TableColumnBuilder<DataFile, KeyPathComparator<DataFile>>
    private var columns: some TableColumnContent<DataFile, KeyPathComparator<DataFile>> {
        TableColumn("#", value: \.order) { (file: DataFile) in
            Text(String(format: "%02d", file.order))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .width(min: 30, ideal: 36, max: 44)

        TableColumn("Name", value: \.name) { (file: DataFile) in
            HStack(spacing: 6) {
                Image(systemName: file.icon)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(file.name)
                    .lineLimit(1)
            }
        }
        .width(min: 150, ideal: 250, max: 400)

        TableColumn("Size", value: \.fileSize) { (file: DataFile) in
            Text(String(format: "%.1f MB", file.fileSizeMB))
                .font(.system(.body, design: .monospaced))
        }
        .width(min: 60, ideal: 72, max: 90)

        TableColumn("Type", value: \.name) { (file: DataFile) in
            let label = file.isDirectory ? "Folder" : file.fileExtension.uppercased()
            Text(label)
                .font(.caption2).fontWeight(.medium)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    (file.isDirectory ? Color.blue : Color.gray).opacity(0.15),
                    in: .capsule
                )
                .foregroundStyle(file.isDirectory ? .blue : .secondary)
        }
        .width(min: 50, ideal: 60, max: 72)
    }

    // MARK: - Rows

    @TableRowBuilder<DataFile>
    private var rows: some TableRowContent<DataFile> {
        ForEach(dataDiscManager.files) { file in
            TableRow(file)
                .draggable(DataFileTransfer(id: file.id))
        }
        .onInsert(of: [.dataFileID]) { offset, providers in
            guard let provider = providers.first else { return }
            Task { @MainActor in
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.dataFileID.identifier) as? Data,
                   let transfer = try? JSONDecoder().decode(DataFileTransfer.self, from: data),
                   let sourceIndex = dataDiscManager.files.firstIndex(where: { $0.id == transfer.id }) {
                    dataDiscManager.moveFiles(from: IndexSet(integer: sourceIndex), to: offset)
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for selectedIDs: Set<DataFile.ID>) -> some View {
        let selectedFiles = dataDiscManager.files.filter { selectedIDs.contains($0.id) }

        if selectedFiles.count == 1, let file = selectedFiles.first {
            if let index = dataDiscManager.files.firstIndex(where: { $0.id == file.id }) {
                Button {
                    dataDiscManager.moveFiles(from: IndexSet(integer: index), to: max(0, index - 1))
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(index == 0)

                Button {
                    dataDiscManager.moveFiles(from: IndexSet(integer: index), to: min(dataDiscManager.files.count, index + 2))
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(index >= dataDiscManager.files.count - 1)

                Divider()
            }
        }

        Button(role: .destructive) {
            let offsets = IndexSet(
                dataDiscManager.files.indices.filter { selectedIDs.contains(dataDiscManager.files[$0].id) }
            )
            dataDiscManager.removeFiles(at: offsets)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
