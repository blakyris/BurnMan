import SwiftUI

struct DiscImageBurnSection: View {
    @Environment(DiskImageManager.self) private var diskImageManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @State private var showFilePicker = false
    @State private var showLog = false
    private var canStartBurn: Bool {
        diskImageManager.cueFile != nil && deviceManager.selectedDevice != nil && diskImageManager.missingFiles.isEmpty
    }

    var body: some View {
        VStack(spacing: 20) {
            fileSelectionSection

            if let cueFile = diskImageManager.cueFile {
                trackInfoSection(cueFile)
            }

            settingsSection

            if diskImageManager.isRunning || !diskImageManager.burnProgress.phase.isActive && diskImageManager.burnProgress.phase != .idle {
                progressSection
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.init(filenameExtension: "cue")!],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                diskImageManager.loadCueFile(url: url)
            }
        }
        .sheet(isPresented: $showLog) {
            LogSheetView(title: "cdrdao Log", log: diskImageManager.log)
        }
        .bindTaskContext(canExecute: canStartBurn, isRunning: diskImageManager.isRunning) {
            TaskBinding(
                canExecute: canStartBurn,
                isRunning: diskImageManager.isRunning,
                onExecute: { startBurn(simulate: false) },
                onSimulate: { startBurn(simulate: true) },
                onCancel: { diskImageManager.cancelBurn() },
                onOpenCue: { showFilePicker = true },
                statusText: diskImageManager.isRunning ? "Burning disc image…" : ""
            )
        }
    }

    // MARK: - File Selection

    private var fileSelectionSection: some View {
        SectionContainer(title: "Source File", systemImage: "doc.badge.gearshape") {
            VStack(spacing: 16) {
                if let cueFile = diskImageManager.cueFile {
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

                    if !diskImageManager.missingFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Missing Files", systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                            ForEach(diskImageManager.missingFiles, id: \.self) { file in
                                Text(file)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(8)
                    }
                } else {
                    EmptyDropZone(
                        icon: "opticaldisc",
                        title: "Select a .cue file",
                        subtitle: "Or drag and drop a file here",
                        buttonLabel: "Open .cue File",
                        showsBackground: false,
                        onAdd: { showFilePicker = true }
                    )
                }
            }
        }
        .fileDrop(extensions: ["cue"]) { urls in
            if let url = urls.first {
                diskImageManager.loadCueFile(url: url)
            }
        }
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
        @Bindable var diskImageManager = diskImageManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Speed",
                    systemImage: "speedometer",
                    description: "Lower speeds reduce errors and improve burn quality."
                ) {
                    Picker("", selection: $diskImageManager.burnSettings.speed) {
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
                    Toggle("", isOn: $diskImageManager.burnSettings.rawMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Swap Audio Bytes",
                    systemImage: "arrow.left.arrow.right",
                    description: "Enable if audio sounds distorted after burning."
                ) {
                    Toggle("", isOn: $diskImageManager.burnSettings.swapAudio)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Eject after burning",
                    systemImage: "eject",
                    description: "Automatically eject disc when burning is complete."
                ) {
                    Toggle("", isOn: $diskImageManager.burnSettings.eject)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Overburn",
                    systemImage: "exclamationmark.triangle",
                    description: "Burn beyond the rated disc capacity. Not supported by all drives."
                ) {
                    Toggle("", isOn: $diskImageManager.burnSettings.overburn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .disabled(diskImageManager.isRunning)
        }
    }

    // MARK: - Progress

    private var progressSection: some View {
        SectionContainer(title: "Progress", systemImage: "flame") {
            BurnProgressView(
                progress: diskImageManager.burnProgress,
                tracks: diskImageManager.cueFile?.tracks ?? [],
                onDismiss: {
                    diskImageManager.burnProgress = BurnProgress()
                },
                onRetry: {
                    startBurn(simulate: diskImageManager.burnSettings.simulate)
                }
            )
        }
    }

    // MARK: - Actions

    private func startBurn(simulate: Bool) {
        guard let device = deviceManager.selectedDevice else { return }
        diskImageManager.burnSettings.simulate = simulate
        Task {
            await diskImageManager.startBurn(device: device)
        }
    }

}
