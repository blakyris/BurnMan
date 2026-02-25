import SwiftUI

struct DiscImageBurnSection: View {
    @Environment(BurnManager.self) private var burnManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @State private var showFilePicker = false
    @State private var showLog = false
    @State private var isDragTargeted = false

    private var canStartBurn: Bool {
        burnManager.cueFile != nil && deviceManager.selectedDevice != nil && burnManager.missingFiles.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            fileSelectionSection

            if let cueFile = burnManager.cueFile {
                trackInfoSection(cueFile)
            }

            settingsSection

            if burnManager.isRunning || !burnManager.progress.phase.isActive && burnManager.progress.phase != .idle {
                progressSection
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.init(filenameExtension: "cue")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                burnManager.loadCueFile(url: url)
            }
        }
        .sheet(isPresented: $showLog) {
            LogSheetView(title: "cdrdao Log", log: burnManager.log)
        }
        .onAppear { updateTaskContext() }
        .onChange(of: canStartBurn) { updateTaskContext() }
        .onChange(of: burnManager.isRunning) { updateTaskContext() }
    }

    private func updateTaskContext() {
        taskContext.actionLabel = "Burn"
        taskContext.actionIcon = "flame"
        taskContext.canExecute = canStartBurn
        taskContext.isRunning = burnManager.isRunning
        taskContext.onExecute = { startBurn(simulate: false) }
        taskContext.onSimulate = { startBurn(simulate: true) }
        taskContext.onCancel = { burnManager.cancel() }
        taskContext.onAddFiles = nil
        taskContext.onOpenCue = { showFilePicker = true }
        taskContext.onSaveCue = nil
        taskContext.statusText = burnManager.isRunning ? "Burning disc image…" : ""
    }

    // MARK: - File Selection

    private var fileSelectionSection: some View {
        SectionContainer(title: "Source File", systemImage: "doc.badge.gearshape") {
            VStack(spacing: 16) {
                if let cueFile = burnManager.cueFile {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(cueFile.name)
                                .font(.headline)
                            Text("\(cueFile.trackCount) track(s) — \(String(format: "%.1f", cueFile.totalSizeMB)) MB")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Change") {
                            showFilePicker = true
                        }
                    }
                    .padding(8)

                    if !burnManager.missingFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Missing Files", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                            ForEach(burnManager.missingFiles, id: \.self) { file in
                                Text(file)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("Select a .cue file")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Or drag and drop a file here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Button("Open .cue File") {
                            showFilePicker = true
                        }
                        .buttonStyle(.glass)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .dropHighlight(isTargeted: isDragTargeted)
    }

    // MARK: - Track Info

    private func trackInfoSection(_ cueFile: CueFile) -> some View {
        SectionContainer(title: "Tracks (\(cueFile.dataTrackCount) data, \(cueFile.audioTrackCount) audio)", systemImage: "music.note.list") {
            VStack(spacing: 0) {
                ForEach(cueFile.tracks) { track in
                    TrackRowView(track: track, showFileName: true)

                    if track.id != cueFile.tracks.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var burnManager = burnManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Speed",
                    systemImage: "speedometer",
                    description: "Lower speeds reduce errors and improve burn quality."
                ) {
                    Picker("", selection: $burnManager.settings.speed) {
                        ForEach(BurnSettings.availableSpeeds, id: \.self) { speed in
                            Text("\(speed)x").tag(speed)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "RAW Mode",
                    systemImage: "waveform",
                    description: "Required for burning some game discs. Copies data as-is."
                ) {
                    Toggle("", isOn: $burnManager.settings.rawMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Swap Audio Bytes",
                    systemImage: "arrow.left.arrow.right",
                    description: "Enable if audio sounds distorted after burning."
                ) {
                    Toggle("", isOn: $burnManager.settings.swapAudio)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Eject after burning",
                    systemImage: "eject",
                    description: "Automatically eject disc when burning is complete."
                ) {
                    Toggle("", isOn: $burnManager.settings.eject)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Overburn",
                    systemImage: "exclamationmark.triangle",
                    description: "Burn beyond the rated disc capacity. Not supported by all drives."
                ) {
                    Toggle("", isOn: $burnManager.settings.overburn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .disabled(burnManager.isRunning)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        SectionContainer(title: "Progress", systemImage: "flame") {
            BurnProgressView(
                progress: burnManager.progress,
                tracks: burnManager.cueFile?.tracks ?? [],
                onDismiss: {
                    burnManager.progress = BurnProgress()
                },
                onRetry: {
                    startBurn(simulate: burnManager.settings.simulate)
                }
            )
        }
    }

    // MARK: - Actions

    private func startBurn(simulate: Bool) {
        guard let device = deviceManager.selectedDevice else { return }
        burnManager.settings.simulate = simulate
        Task {
            await burnManager.startBurn(device: device)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil),
                  url.pathExtension.lowercased() == "cue" else { return }
            Task { @MainActor in
                burnManager.loadCueFile(url: url)
            }
        }
        return true
    }
}
