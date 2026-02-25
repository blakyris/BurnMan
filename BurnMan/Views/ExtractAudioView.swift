import SwiftUI

struct ExtractAudioView: View {
    @Environment(ExtractAudioManager.self) private var extractAudioManager
    @Environment(DeviceManager.self) private var deviceManager

    private var canReadTOC: Bool {
        deviceManager.selectedDevice != nil && !extractAudioManager.isRunning
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                tocSection

                if !extractAudioManager.tracks.isEmpty {
                    trackListSection
                    outputSection
                }

                if extractAudioManager.state != .idle {
                    statusSection
                }

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Extraire les pistes audio")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - TOC

    private var tocSection: some View {
        SectionContainer(title: "Table des matières", systemImage: "list.number") {
            VStack(spacing: 12) {
                if extractAudioManager.tracks.isEmpty {
                    HStack {
                        Label {
                            Text("Insérez un CD audio puis lisez la table des matières pour voir les pistes.")
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
                        Text("\(extractAudioManager.tracks.count) piste(s) détectée(s)")
                            .font(.subheadline)
                        Spacer()
                        Text("\(extractAudioManager.selectedTracks.count) sélectionnée(s)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    readTOC()
                } label: {
                    Label(
                        extractAudioManager.tracks.isEmpty ? "Lire la table des matières" : "Relire",
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
        SectionContainer(title: "Pistes", systemImage: "music.note.list") {
            VStack(spacing: 8) {
                HStack {
                    Button("Tout sélectionner") {
                        extractAudioManager.selectAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Button("Tout désélectionner") {
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
        HStack {
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
        }
        .padding(.vertical, 2)
    }

    // MARK: - Output

    private var outputSection: some View {
        @Bindable var extractAudioManager = extractAudioManager

        return SectionContainer(title: "Sortie", systemImage: "square.and.arrow.down") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Format",
                    systemImage: "waveform",
                    description: "Le format audio de sortie pour les pistes extraites."
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
                        title: "Débit MP3",
                        systemImage: "speedometer",
                        description: "Débit binaire pour l'encodage MP3 (kbps)."
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

                // Output directory
                HStack {
                    if let url = extractAudioManager.outputDirectory {
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
                        extractAudioManager.outputDirectory == nil ? "Choisir le dossier de sortie" : "Modifier",
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
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch extractAudioManager.state {
                case .reading:
                    ProgressView()
                        .controlSize(.small)
                    Text("Lecture du disque...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .extracting(let current, let total):
                    ProgressView(value: Double(current), total: Double(total))
                    Text("Extraction piste \(current)/\(total)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Extraction terminée")
                case .failed:
                    if let error = extractAudioManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text(extractAudioManager.state.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if extractAudioManager.isRunning {
                    Button(role: .destructive) {
                        extractAudioManager.cancel()
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        startExtraction()
                    } label: {
                        Label("Extraire", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!extractAudioManager.canExtract)
                    .controlSize(.large)
                }
            }
        }
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
        panel.title = "Dossier de sortie"
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
