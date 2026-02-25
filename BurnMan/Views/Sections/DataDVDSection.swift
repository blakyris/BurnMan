import SwiftUI
import UniformTypeIdentifiers

struct DataDVDSection: View {
    @Environment(DataDiscManager.self) private var dataDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @State private var isDragTargeted = false

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
        .onAppear { updateTaskContext() }
        .onChange(of: dataDiscManager.files.count) { updateTaskContext() }
        .onChange(of: dataDiscManager.isRunning) { updateTaskContext() }
    }

    private func updateTaskContext() {
        let canStart = !dataDiscManager.files.isEmpty && deviceManager.selectedDevice != nil
        taskContext.actionLabel = "Burn"
        taskContext.actionIcon = "flame"
        taskContext.canExecute = canStart
        taskContext.isRunning = dataDiscManager.isRunning
        taskContext.onExecute = { startBurn() }
        taskContext.onSimulate = nil
        taskContext.onCancel = { dataDiscManager.cancel() }
        taskContext.onAddFiles = { openFilePicker() }
        taskContext.statusText = dataDiscManager.isRunning ? "Burning data DVD…" : ""
    }

    // MARK: - Files

    private var filesSection: some View {
        SectionContainer(title: "Files", systemImage: "folder.fill") {
            if dataDiscManager.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Add files or folders")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Drag and drop files here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("Add Files") {
                        openFilePicker()
                    }
                    .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
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
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .dropHighlight(isTargeted: isDragTargeted)
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
        SectionContainer(title: "Progress", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch dataDiscManager.state {
                case .burning:
                    ProgressView()
                        .controlSize(.small)
                    Text("Burning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Burn complete")
                case .failed:
                    if let error = dataDiscManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private func startBurn() {
        guard let device = deviceManager.selectedDevice else { return }
        dataDiscManager.targetMedia = .dvd
        Task {
            await dataDiscManager.startBurn(device: device.path)
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

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    dataDiscManager.addFiles(urls: [url])
                }
            }
            handled = true
        }
        return handled
    }
}
