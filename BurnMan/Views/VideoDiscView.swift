import SwiftUI
import UniformTypeIdentifiers

struct VideoDiscView: View {
    @Environment(VideoDiscManager.self) private var videoDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @State private var isDragTargeted = false

    private var canStartBurn: Bool {
        !videoDiscManager.files.isEmpty && deviceManager.selectedDevice != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                filesSection
                settingsSection

                if videoDiscManager.state != .idle {
                    statusSection
                }

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Disque vidéo")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        SectionContainer(title: "Fichiers vidéo", systemImage: "play.rectangle") {
            if videoDiscManager.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "play.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Ajoute des fichiers vidéo")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("MKV, MP4, AVI, MOV — ou glisse-dépose ici")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button("Ajouter des fichiers") {
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

                            Text(String(format: "%.1f Mo", file.fileSizeMB))
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
                        Label("Ajouter", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)

                    Spacer()

                    Text("\(videoDiscManager.files.count) fichier(s)")
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

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var videoDiscManager = videoDiscManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            SettingRow(
                title: "Type de disque",
                systemImage: "opticaldisc",
                description: "DVD pour la compatibilité, Blu-ray pour la haute définition."
            ) {
                Picker("", selection: $videoDiscManager.discType) {
                    Text("DVD").tag(VideoDiscType.dvd)
                    Text("Blu-ray").tag(VideoDiscType.bluray)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch videoDiscManager.state {
                case .converting(let current, let total):
                    ProgressView(value: Double(current), total: Double(total))
                    Text("Transcodage \(current)/\(total)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .burning:
                    ProgressView()
                        .controlSize(.small)
                    Text("Gravure en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Gravure terminée")
                case .failed:
                    if let error = videoDiscManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text("Préparation...")
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
                if videoDiscManager.isRunning {
                    Button(role: .destructive) {
                        videoDiscManager.cancel()
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        startBurn()
                    } label: {
                        Label("Graver", systemImage: "flame")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canStartBurn)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Actions

    private func startBurn() {
        guard let device = deviceManager.selectedDevice else { return }
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
