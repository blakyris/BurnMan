import SwiftUI

struct ExtractVideoView: View {
    @Environment(ExtractVideoManager.self) private var extractVideoManager
    @Environment(DeviceManager.self) private var deviceManager

    private var canProbe: Bool {
        deviceManager.selectedDevice != nil && !extractVideoManager.isRunning
    }

    var body: some View {
        ScrollView {
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

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Extraire un film")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - Probe

    private var probeSection: some View {
        SectionContainer(title: "Analyse du disque", systemImage: "magnifyingglass") {
            VStack(spacing: 12) {
                if extractVideoManager.titles.isEmpty {
                    HStack {
                        Label {
                            Text("Insérez un DVD ou Blu-ray puis analysez le disque pour détecter les titres.")
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
                        Text("\(extractVideoManager.titles.count) titre(s) détecté(s)")
                            .font(.subheadline)
                        Spacer()
                    }
                }

                Button {
                    probeTitles()
                } label: {
                    Label(
                        extractVideoManager.titles.isEmpty ? "Analyser le disque" : "Relancer l'analyse",
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
        @Bindable var extractVideoManager = extractVideoManager

        return SectionContainer(title: "Titres", systemImage: "film") {
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
                    Text("Titre \(title.id)")
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        Text(title.durationFormatted)

                        if title.chapters > 0 {
                            Text("\(title.chapters) chapitres")
                        }

                        if !title.audioStreams.isEmpty {
                            Text("\(title.audioStreams.count) audio")
                        }

                        if !title.subtitleStreams.isEmpty {
                            Text("\(title.subtitleStreams.count) sous-titres")
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

        return SectionContainer(title: "Sortie", systemImage: "square.and.arrow.down") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Format",
                    systemImage: "film",
                    description: "MKV copie les flux sans transcodage. MP4 transcode en H.264."
                ) {
                    Picker("", selection: $extractVideoManager.outputFormat) {
                        Text("MKV").tag(VideoOutputFormat.mkv)
                        Text("MP4").tag(VideoOutputFormat.mp4)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                // Output file
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
                        extractVideoManager.outputURL == nil ? "Choisir l'emplacement" : "Modifier",
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
                        "libdvdcss non trouvé. L'extraction de DVD protégés nécessite libdvdcss. Installez-le : brew install libdvdcss"
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
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch extractVideoManager.state {
                case .preparing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Analyse en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .extracting:
                    ProgressView(value: extractVideoManager.progress)
                    Text("Extraction en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Extraction terminée")
                case .failed:
                    if let error = extractVideoManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text(extractVideoManager.state.displayName)
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
                if extractVideoManager.isRunning {
                    Button(role: .destructive) {
                        extractVideoManager.cancel()
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
                    .disabled(!extractVideoManager.canExtract)
                    .controlSize(.large)
                }
            }
        }
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
        panel.title = "Enregistrer le film"
        panel.nameFieldStringValue = "film.\(extractVideoManager.outputFormat.fileExtension)"

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
