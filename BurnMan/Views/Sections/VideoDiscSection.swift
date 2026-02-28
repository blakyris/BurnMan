import SwiftUI
import UniformTypeIdentifiers

struct VideoDiscSection: View {
    let targetMedia: TargetMedia

    @Environment(VideoDiscManager.self) private var videoDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

    private var mediaLabel: String {
        switch targetMedia {
        case .dvd: "DVD"
        case .bluray: "Blu-ray"
        case .cd: "CD"
        }
    }

    var body: some View {
        VStack(spacing: 20) {
            filesSection

            if videoDiscManager.state != .idle {
                statusSection
            }
        }
        .bindTaskContext(
            canExecute: !videoDiscManager.files.isEmpty && deviceManager.selectedDevice != nil,
            isRunning: videoDiscManager.isRunning
        ) {
            TaskBinding(
                canExecute: !videoDiscManager.files.isEmpty && deviceManager.selectedDevice != nil,
                isRunning: videoDiscManager.isRunning,
                onExecute: { startBurn() },
                onCancel: { videoDiscManager.cancel() },
                onAddFiles: { openFilePicker() },
                statusText: videoDiscManager.isRunning ? "Burning \(mediaLabel) video…" : ""
            )
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        SectionContainer(title: "Video Files", systemImage: "play.rectangle") {
            if videoDiscManager.files.isEmpty {
                EmptyDropZone(
                    icon: "play.rectangle",
                    title: "Add video files",
                    subtitle: "MKV, MP4, AVI, MOV — or drag and drop here",
                    showsBackground: false,
                    onAdd: { openFilePicker() }
                )
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
        .fileDrop(extensions: ["mkv", "mp4", "avi", "mov", "m4v", "mpg", "mpeg"]) { urls in
            Task {
                await videoDiscManager.addFiles(urls: urls)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        PipelineStatusView(
            state: videoDiscManager.state,
            error: videoDiscManager.error,
            completionMessage: "Burn complete",
            progress: convertingProgress
        )
    }

    private var convertingProgress: Double? {
        if case .converting(let current, let total) = videoDiscManager.state, total > 0 {
            return Double(current) / Double(total)
        }
        return nil
    }

    // MARK: - Actions

    private func startBurn() {
        guard let device = deviceManager.selectedDevice else { return }
        videoDiscManager.discType = targetMedia == .bluray ? .bluray : .dvd
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
}
