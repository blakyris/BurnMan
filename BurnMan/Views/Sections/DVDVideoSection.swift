import SwiftUI
import UniformTypeIdentifiers

struct DVDVideoSection: View {
    @Environment(VideoDiscManager.self) private var videoDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @State private var isDragTargeted = false

    var body: some View {
        VStack(spacing: 20) {
            filesSection

            if videoDiscManager.state != .idle {
                statusSection
            }
        }
        .onAppear { updateTaskContext() }
        .onChange(of: videoDiscManager.files.count) { updateTaskContext() }
        .onChange(of: videoDiscManager.isRunning) { updateTaskContext() }
    }

    private func updateTaskContext() {
        let canStart = !videoDiscManager.files.isEmpty && deviceManager.selectedDevice != nil
        taskContext.actionLabel = "Burn"
        taskContext.actionIcon = "flame"
        taskContext.canExecute = canStart
        taskContext.isRunning = videoDiscManager.isRunning
        taskContext.onExecute = { startBurn() }
        taskContext.onSimulate = nil
        taskContext.onCancel = { videoDiscManager.cancel() }
        taskContext.onAddFiles = { openFilePicker() }
        taskContext.onOpenCue = nil
        taskContext.onSaveCue = nil
        taskContext.statusText = videoDiscManager.isRunning ? "Burning DVD video…" : ""
    }

    // MARK: - Files

    private var filesSection: some View {
        SectionContainer(title: "Video Files", systemImage: "play.rectangle") {
            if videoDiscManager.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Add video files")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("MKV, MP4, AVI, MOV — or drag and drop here")
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
                    ForEach(videoDiscManager.files) { file in
                        HStack(spacing: 10) {
                            Image(systemName: "film")
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text("\(file.codec) \(file.resolution)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(file.durationFormatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)

                            Text(String(format: "%.1f MB", file.fileSizeMB))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 8)

                        if file.id != videoDiscManager.files.last?.id {
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

                    Text("\(videoDiscManager.files.count) file(s)")
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

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progress", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch videoDiscManager.state {
                case .converting(let current, let total):
                    ProgressView(value: Double(current), total: Double(total))
                    Text("Transcoding \(current)/\(total)…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .burning:
                    ProgressView()
                        .controlSize(.small)
                    Text("Burning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Burn complete")
                case .failed:
                    if let error = videoDiscManager.error {
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
        videoDiscManager.discType = .dvd
        Task {
            await videoDiscManager.startBurn(device: device.path)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        var types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
        if let mkv = UTType(filenameExtension: "mkv") { types.append(mkv) }
        panel.allowedContentTypes = types

        panel.begin { response in
            if response == .OK {
                let urls = panel.urls
                Task { @MainActor in
                    await videoDiscManager.addFiles(urls: urls)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        let videoExtensions = Set(["mkv", "mp4", "avi", "mov", "m4v", "mpg", "mpeg"])

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      videoExtensions.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in
                    await videoDiscManager.addFiles(urls: [url])
                }
            }
            handled = true
        }
        return handled
    }
}
