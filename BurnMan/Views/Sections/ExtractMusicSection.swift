import SwiftUI

struct ExtractMusicSection: View {
    @Environment(ExtractAudioManager.self) private var extractAudioManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

    private var canReadTOC: Bool {
        deviceManager.selectedDevice != nil && !extractAudioManager.isRunning
    }

    var body: some View {
        VStack(spacing: 20) {
            tocSection

            if !extractAudioManager.tracks.isEmpty {
                trackListSection
                outputSection
            }

            if extractAudioManager.state != .idle {
                statusSection
            }
        }
        .bindTaskContext(canExecute: extractAudioManager.canExtract, isRunning: extractAudioManager.isRunning) {
            TaskBinding(
                actionLabel: "Extract",
                actionIcon: "arrow.down.circle",
                canExecute: extractAudioManager.canExtract,
                isRunning: extractAudioManager.isRunning,
                onExecute: { startExtraction() },
                onCancel: { extractAudioManager.cancel() },
                statusText: extractAudioManager.isRunning ? "Extracting audio…" : ""
            )
        }
    }

    // MARK: - TOC

    private var tocSection: some View {
        SectionContainer(title: "Table of Contents", systemImage: "list.number") {
            VStack(spacing: 12) {
                if extractAudioManager.tracks.isEmpty {
                    HStack {
                        Label {
                            Text("Insert an audio CD then read the table of contents to see the tracks.")
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
                        Text("\(extractAudioManager.tracks.count) track(s) detected")
                            .font(.subheadline)
                        Spacer()
                        Text("\(extractAudioManager.selectedTracks.count) selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    readTOC()
                } label: {
                    Label(
                        extractAudioManager.tracks.isEmpty ? "Read Table of Contents" : "Re-read",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.caption)
                }
                .buttonStyle(.glass)
                .disabled(!canReadTOC)
            }
        }
    }

    // MARK: - Track List

    private var trackListSection: some View {
        SectionContainer(title: "Tracks", systemImage: "music.note.list") {
            VStack(spacing: 8) {
                HStack {
                    Button("Select All") {
                        extractAudioManager.selectAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Button("Deselect All") {
                        extractAudioManager.deselectAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)

                    Spacer()
                }

                ForEach(extractAudioManager.tracks) { track in
                    trackRow(track)
                }
            }
        }
    }

    private func trackRow(_ track: CDTrackEntry) -> some View {
        Button {
            extractAudioManager.toggleTrack(track.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: track.selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(track.selected ? Color.accentColor : .secondary)
                    .imageScale(.medium)

                Text("\(track.id)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)

                Text(track.title)
                    .font(.subheadline)

                Spacer()

                if track.durationSeconds > 0 {
                    Text(track.durationFormatted)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Output

    private var outputSection: some View {
        @Bindable var extractAudioManager = extractAudioManager

        return SectionContainer(title: "Output", systemImage: "square.and.arrow.down") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Format",
                    systemImage: "waveform",
                    description: "Output audio format for extracted tracks."
                ) {
                    Picker("", selection: $extractAudioManager.outputFormat) {
                        Text("FLAC").tag(AudioOutputFormat.flac)
                        Text("WAV").tag(AudioOutputFormat.wav)
                        Text("MP3").tag(AudioOutputFormat.mp3)
                        Text("AAC").tag(AudioOutputFormat.aac)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if extractAudioManager.outputFormat == .mp3 {
                    SettingRow(
                        title: "MP3 Bitrate",
                        systemImage: "speedometer",
                        description: "Bitrate for MP3 encoding (kbps)."
                    ) {
                        Picker("", selection: $extractAudioManager.mp3Bitrate) {
                            Text("128").tag(128)
                            Text("192").tag(192)
                            Text("256").tag(256)
                            Text("320").tag(320)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }

                if let url = extractAudioManager.outputDirectory {
                    HStack {
                        Image(systemName: "folder")
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
                    chooseOutputDirectory()
                } label: {
                    Label(
                        extractAudioManager.outputDirectory == nil ? "Choose Output Folder" : "Change",
                        systemImage: "folder"
                    )
                    .font(.caption)
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        PipelineStatusView(
            state: extractAudioManager.state,
            error: extractAudioManager.error,
            completionMessage: "Extraction complete",
            progress: extractingProgress
        )
    }

    private var extractingProgress: Double? {
        if case .extracting(let current, let total) = extractAudioManager.state, total > 0 {
            return Double(current) / Double(total)
        }
        return nil
    }

    // MARK: - Actions

    private func readTOC() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await extractAudioManager.readTOC(device: device.path)
        }
    }

    private func startExtraction() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await extractAudioManager.extract(device: device.path)
        }
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "Output Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true

        panel.begin { response in
            if response == .OK, let url = panel.url {
                extractAudioManager.outputDirectory = url
            }
        }
    }
}
