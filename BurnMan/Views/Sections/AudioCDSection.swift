import SwiftUI
import UniformTypeIdentifiers

struct AudioCDSection: View {
    @Environment(AudioCDManager.self) private var audioCDManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @State private var showLog = false
    @State private var isDragTargeted = false
    @State private var selection: Set<AudioTrack.ID> = []

    var body: some View {
        VStack(spacing: 20) {
            tracksSection

            if !audioCDManager.tracks.isEmpty {
                capacitySection
                cdTextSection
            }

            settingsSection

            if audioCDManager.isRunning || audioCDManager.progress.pipelinePhase != .idle {
                progressSection
            }
        }
        .sheet(isPresented: $showLog) {
            LogSheetView(title: "Audio CD Log", log: audioCDManager.log)
        }
        .onAppear { updateTaskContext() }
        .onChange(of: audioCDManager.canBurn) { updateTaskContext() }
        .onChange(of: audioCDManager.isRunning) { updateTaskContext() }
    }

    // MARK: - Task Context

    private func updateTaskContext() {
        let canStart = audioCDManager.canBurn && deviceManager.selectedDevice != nil
        taskContext.actionLabel = "Burn"
        taskContext.actionIcon = "flame"
        taskContext.canExecute = canStart
        taskContext.isRunning = audioCDManager.isRunning
        taskContext.onExecute = { startPipeline(simulate: false) }
        taskContext.onSimulate = { startPipeline(simulate: true) }
        taskContext.onCancel = { audioCDManager.cancel() }
        taskContext.onAddFiles = { openFilePicker() }
        taskContext.onOpenCue = nil
        taskContext.onSaveCue = nil

        if case .burning = audioCDManager.progress.pipelinePhase {
            taskContext.statusText = "Burning audio CD…"
        } else if case .converting = audioCDManager.progress.pipelinePhase {
            taskContext.statusText = "Converting tracks…"
        } else {
            taskContext.statusText = ""
        }
    }

    // MARK: - Tracks Section

    private var tracksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio Tracks", systemImage: "music.note.list")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if audioCDManager.tracks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "music.note")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Add audio files")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("MP3, AAC, FLAC, WAV, AIFF — or drag and drop here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("Add Files") {
                        openFilePicker()
                    }
                    .buttonStyle(.glass)
                }
                .frame(maxWidth: .infinity)
                .padding(24)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    List(selection: $selection) {
                        ForEach(Array(audioCDManager.tracks.enumerated()), id: \.element.id) { index, track in
                            AudioTrackRowView(
                                track: track,
                                onMoveUp: index > 0 ? {
                                    audioCDManager.moveTrack(from: IndexSet(integer: index), to: index - 1)
                                } : nil,
                                onMoveDown: index < audioCDManager.tracks.count - 1 ? {
                                    audioCDManager.moveTrack(from: IndexSet(integer: index), to: index + 2)
                                } : nil,
                                onRemove: {
                                    audioCDManager.removeTrack(at: IndexSet(integer: index))
                                }
                            )
                        }
                        .onMove { source, destination in
                            audioCDManager.moveTrack(from: source, to: destination)
                        }
                    }
                    .listStyle(.bordered(alternatesRowBackgrounds: true))
                    .scrollContentBackground(.visible)
                    .frame(height: 10 * 44)

                    HStack(spacing: 0) {
                        Button {
                            openFilePicker()
                        } label: {
                            Image(systemName: "plus")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(.borderless)

                        Divider()
                            .frame(height: 16)

                        Button {
                            let offsets = IndexSet(
                                audioCDManager.tracks.indices.filter { selection.contains(audioCDManager.tracks[$0].id) }
                            )
                            audioCDManager.removeTrack(at: offsets)
                            selection.removeAll()
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 24, height: 20)
                        }
                        .buttonStyle(.borderless)
                        .disabled(selection.isEmpty)

                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(.bar)
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator)
                )
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .dropHighlight(isTargeted: isDragTargeted)
    }

    // MARK: - Capacity Section

    private var capacitySection: some View {
        SectionContainer(title: "Capacity", systemImage: "chart.bar") {
            VStack(spacing: 10) {
                ProgressView(
                    value: min(audioCDManager.capacityFraction, 1.0),
                    total: 1.0
                )
                .tint(capacityColor)

                HStack {
                    let totalMin = Int(audioCDManager.totalDurationSeconds) / 60
                    let totalSec = Int(audioCDManager.totalDurationSeconds) % 60
                    Text("\(totalMin):\(String(format: "%02d", totalSec))")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)

                    Text("/")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(audioCDManager.settings.cdType.maxSeconds / 60):00")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(audioCDManager.tracks.count) track(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !audioCDManager.tracksNeedingConversion.isEmpty {
                        Text("·")
                            .foregroundStyle(.secondary)
                        Text("\(audioCDManager.tracksNeedingConversion.count) to convert")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if audioCDManager.isOverCapacity {
                    Label("Duration exceeds CD capacity", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var capacityColor: Color {
        if audioCDManager.capacityFraction > 1.0 { return .red }
        if audioCDManager.capacityFraction > 0.9 { return .orange }
        return .green
    }

    // MARK: - CD-Text Section

    private var cdTextSection: some View {
        @Bindable var audioCDManager = audioCDManager

        return SectionContainer(title: "Metadata", systemImage: "text.quote") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        Task { await audioCDManager.fillMetadataFromFiles() }
                    } label: {
                        Label("Auto-fill", systemImage: "arrow.down.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)

                    Spacer()
                }

                DisclosureGroup("Edit Metadata") {
                    VStack(spacing: 16) {
                        VStack(spacing: 10) {
                            Text("Disc")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                cdTextField("Album Title", text: $audioCDManager.cdText.albumTitle)
                                cdTextField("Artist", text: $audioCDManager.cdText.albumArtist)
                            }

                            HStack(spacing: 12) {
                                cdTextField("Songwriter", text: $audioCDManager.cdText.albumSongwriter)
                                cdTextField("Message", text: $audioCDManager.cdText.albumMessage)
                            }

                            HStack(spacing: 12) {
                                cdTextField("UPC/EAN", text: $audioCDManager.cdText.upcEan)
                                Spacer()
                            }
                        }

                        Divider()

                        VStack(spacing: 10) {
                            Text("Tracks")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach($audioCDManager.tracks) { $track in
                                DisclosureGroup {
                                    VStack(spacing: 8) {
                                        HStack(spacing: 12) {
                                            cdTextField("Title", text: $track.title)
                                            cdTextField("Artist", text: $track.artist)
                                        }
                                        HStack(spacing: 12) {
                                            cdTextField("Songwriter", text: $track.songwriter)
                                            cdTextField("ISRC", text: $track.isrc)
                                        }
                                        cdTextField("Message", text: $track.message)
                                    }
                                    .padding(.top, 4)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(String(format: "%02d", track.order))
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)
                                        Text(track.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        if !track.artist.isEmpty {
                                            Text("—")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                            Text(track.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
    }

    private func cdTextField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        @Bindable var audioCDManager = audioCDManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Speed",
                    systemImage: "speedometer",
                    description: "Lower speeds reduce errors and improve burn quality."
                ) {
                    Picker("", selection: $audioCDManager.settings.speed) {
                        ForEach(AudioCDSettings.availableSpeeds, id: \.self) { speed in
                            Text("\(speed)x").tag(speed)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "CD Type",
                    systemImage: "opticaldisc",
                    description: "Choose blank disc type: 80 min or 74 min."
                ) {
                    Picker("", selection: $audioCDManager.settings.cdType) {
                        ForEach(CDType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "Eject after burning",
                    systemImage: "eject",
                    description: "Automatically eject disc when burning is complete."
                ) {
                    Toggle("", isOn: $audioCDManager.settings.eject)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Overburn",
                    systemImage: "exclamationmark.triangle",
                    description: "Burn beyond the rated disc capacity. Not supported by all drives."
                ) {
                    Toggle("", isOn: $audioCDManager.settings.overburn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .disabled(audioCDManager.isRunning)
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        SectionContainer(title: "Progress", systemImage: "waveform.path") {
            AudioCDProgressView(
                progress: audioCDManager.progress,
                tracks: audioCDManager.tracks,
                onDismiss: {
                    audioCDManager.progress = AudioCDProgress()
                },
                onRetry: {
                    startPipeline(simulate: audioCDManager.settings.simulate)
                }
            )
        }
    }

    // MARK: - Actions

    private func startPipeline(simulate: Bool) {
        guard let device = deviceManager.selectedDevice else { return }
        audioCDManager.settings.simulate = simulate
        Task {
            await audioCDManager.startPipeline(device: device)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        var types: [UTType] = [.audio, .mp3, .wav, .aiff]
        if let flac = UTType(filenameExtension: "flac") {
            types.append(flac)
        }
        panel.allowedContentTypes = types

        panel.begin { response in
            if response == .OK {
                let urls = panel.urls
                Task { @MainActor in
                    await audioCDManager.addFiles(urls: urls)
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        let audioExtensions = Set(["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"])

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil),
                      audioExtensions.contains(url.pathExtension.lowercased()) else { return }
                Task { @MainActor in
                    await audioCDManager.addFiles(urls: [url])
                }
            }
            handled = true
        }
        return handled
    }
}
