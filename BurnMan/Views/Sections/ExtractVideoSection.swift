import SwiftUI

struct ExtractVideoSection: View {
    @Environment(ExtractVideoManager.self) private var extractVideoManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

    private var canProbe: Bool {
        deviceManager.selectedDevice != nil && !extractVideoManager.isRunning
    }

    var body: some View {
        VStack(spacing: 20) {
            probeSection

            if !extractVideoManager.titles.isEmpty {
                titleListSection
                outputSection
            }

            if !extractVideoManager.decryptionService.isDvdCssAvailable {
                decryptionWarningSection
            }

            if extractVideoManager.state != .idle {
                statusSection
            }
        }
        .bindTaskContext(canExecute: extractVideoManager.canExtract, isRunning: extractVideoManager.isRunning) {
            TaskBinding(
                actionLabel: "Extract",
                actionIcon: "arrow.down.circle",
                canExecute: extractVideoManager.canExtract,
                isRunning: extractVideoManager.isRunning,
                onExecute: { startExtraction() },
                onCancel: { extractVideoManager.cancel() },
                statusText: extractVideoManager.isRunning ? "Extracting video…" : ""
            )
        }
        .onChange(of: extractVideoManager.isRunning) {
            taskContext.progress = extractVideoManager.isRunning ? extractVideoManager.progress : nil
        }
    }

    // MARK: - Probe

    private var probeSection: some View {
        SectionContainer(title: "Disc Analysis", systemImage: "magnifyingglass") {
            VStack(spacing: 12) {
                if extractVideoManager.titles.isEmpty {
                    HStack {
                        Label {
                            Text("Insert a DVD or Blu-ray then analyze the disc to detect titles.")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()
                    }
                } else {
                    HStack {
                        Text("\(extractVideoManager.titles.count) title(s) detected")
                            .font(.subheadline)
                        Spacer()
                    }
                }

                Button {
                    probeTitles()
                } label: {
                    Label(
                        extractVideoManager.titles.isEmpty ? "Analyze Disc" : "Re-analyze",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.caption)
                }
                .buttonStyle(.glass)
                .disabled(!canProbe)
            }
        }
    }

    // MARK: - Title List

    private var titleListSection: some View {
        SectionContainer(title: "Titles", systemImage: "film") {
            VStack(spacing: 8) {
                ForEach(extractVideoManager.titles) { title in
                    titleRow(title)
                }
            }
        }
    }

    private func titleRow(_ title: DVDTitle) -> some View {
        Button {
            extractVideoManager.selectedTitleId = title.id
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName: extractVideoManager.selectedTitleId == title.id
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundStyle(
                    extractVideoManager.selectedTitleId == title.id ? Color.accentColor : Color.secondary
                )
                .imageScale(.medium)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Title \(title.id)")
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        Text(title.durationFormatted)

                        if title.chapters > 0 {
                            Text("\(title.chapters) chapters")
                        }

                        if !title.audioStreams.isEmpty {
                            Text("\(title.audioStreams.count) audio")
                        }

                        if !title.subtitleStreams.isEmpty {
                            Text("\(title.subtitleStreams.count) subtitles")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Output

    private var outputSection: some View {
        @Bindable var extractVideoManager = extractVideoManager

        return SectionContainer(title: "Output", systemImage: "square.and.arrow.down") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Format",
                    systemImage: "film",
                    description: "MKV copies streams without transcoding. MP4 transcodes to H.264."
                ) {
                    Picker("", selection: $extractVideoManager.outputFormat) {
                        Text("MKV").tag(VideoOutputFormat.mkv)
                        Text("MP4").tag(VideoOutputFormat.mp4)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if let url = extractVideoManager.outputURL {
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(url.lastPathComponent)
                            .font(.subheadline)
                            .lineLimit(1)
                        Spacer()
                        Text(url.deletingLastPathComponent().path)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Button {
                    chooseOutputLocation()
                } label: {
                    Label(
                        extractVideoManager.outputURL == nil ? "Choose Location" : "Change",
                        systemImage: "folder"
                    )
                    .font(.caption)
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Decryption Warning

    private var decryptionWarningSection: some View {
        SectionContainer(title: "Protection", systemImage: "lock.shield") {
            HStack {
                Label {
                    Text(
                        "libdvdcss not found. Extracting encrypted DVDs requires libdvdcss. Install it: brew install libdvdcss"
                    )
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Spacer()
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        PipelineStatusView(
            state: extractVideoManager.state,
            error: extractVideoManager.error,
            completionMessage: "Extraction complete",
            progress: extractingProgress
        )
    }

    private var extractingProgress: Double? {
        if case .extracting = extractVideoManager.state {
            return extractVideoManager.progress
        }
        return nil
    }

    // MARK: - Actions

    private func probeTitles() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await extractVideoManager.probeTitles(devicePath: device.path)
        }
    }

    private func startExtraction() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await extractVideoManager.extract(devicePath: device.path)
        }
    }

    private func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.title = "Save Movie"
        panel.nameFieldStringValue = "movie.\(extractVideoManager.outputFormat.fileExtension)"

        panel.allowedContentTypes = [
            .init(filenameExtension: extractVideoManager.outputFormat.fileExtension)!
        ]

        panel.begin { response in
            if response == .OK, let url = panel.url {
                extractVideoManager.outputURL = url
            }
        }
    }
}
