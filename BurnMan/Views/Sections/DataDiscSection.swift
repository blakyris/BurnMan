import SwiftUI
import UniformTypeIdentifiers

/// Shared view for data DVD and data Blu-ray burning.
/// The only difference between the two is `targetMedia` and the status text label.
struct DataDiscSection: View {
    let targetMedia: TargetMedia

    @Environment(DataDiscManager.self) private var dataDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    private var label: String {
        targetMedia == .dvd ? "DVD" : "Blu-ray"
    }

    var body: some View {
        VStack(spacing: 20) {
            filesSection

            if !dataDiscManager.files.isEmpty {
                sizeSection
            }

            settingsSection

            if dataDiscManager.state != .idle {
                statusSection
            }
        }
        .bindTaskContext(
            canExecute: !dataDiscManager.files.isEmpty && deviceManager.selectedDevice != nil,
            isRunning: dataDiscManager.isRunning
        ) {
            TaskBinding(
                canExecute: !dataDiscManager.files.isEmpty && deviceManager.selectedDevice != nil,
                isRunning: dataDiscManager.isRunning,
                onExecute: { startBurn() },
                onCancel: { dataDiscManager.cancel() },
                onAddFiles: { openFilePicker() },
                statusText: dataDiscManager.isRunning ? "Burning data \(label)…" : ""
            )
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        SectionContainer(title: "Files", systemImage: "folder.fill") {
            if dataDiscManager.files.isEmpty {
                EmptyDropZone(
                    icon: "folder.badge.plus",
                    title: "Add files or folders",
                    subtitle: "Drag and drop files here",
                    showsBackground: false,
                    onAdd: { openFilePicker() }
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(dataDiscManager.files) { file in
                        HStack(spacing: 10) {
                            Image(systemName: file.icon)
                                .foregroundStyle(.secondary)

                            Text(file.name)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Text(String(format: "%.1f MB", file.fileSizeMB))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                        if file.id != dataDiscManager.files.last?.id {
                            Divider()
                        }
                    }
                }

                HStack {
                    Button {
                        openFilePicker()
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Text("\(dataDiscManager.files.count) file(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
        .fileDrop { urls in
            dataDiscManager.addFiles(urls: urls)
        }
    }

    // MARK: - Size

    private var sizeSection: some View {
        SectionContainer(title: "Space", systemImage: "chart.bar") {
            HStack {
                Text(String(format: "%.1f MB", dataDiscManager.totalSizeMB))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)

                Spacer()

                Text("\(dataDiscManager.files.count) file(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var dataDiscManager = dataDiscManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            SettingRow(
                title: "Disc Label",
                systemImage: "textformat",
                description: "The label that will appear on the disc."
            ) {
                TextField("", text: $dataDiscManager.discLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        PipelineStatusView(
            state: dataDiscManager.state,
            error: dataDiscManager.error,
            completionMessage: "Burn complete"
        )
    }

    // MARK: - Actions

    private func startBurn() {
        guard let device = deviceManager.selectedDevice else { return }
        dataDiscManager.targetMedia = targetMedia
        Task {
            await dataDiscManager.startBurn(device: device)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]

        panel.begin { response in
            if response == .OK {
                dataDiscManager.addFiles(urls: panel.urls)
            }
        }
    }

}
