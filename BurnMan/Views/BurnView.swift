import SwiftUI

struct BurnView: View {
    @Environment(BurnManager.self) private var burnManager
    @Environment(DeviceManager.self) private var deviceManager
    @State private var showFilePicker = false
    @State private var showLog = false
    @State private var isDragTargeted = false

    private var canStartBurn: Bool {
        burnManager.cueFile != nil && deviceManager.selectedDevice != nil && burnManager.missingFiles.isEmpty
    }

    private var burnHelpString: String {
        if burnManager.cueFile == nil {
            return "Sélectionne un fichier .cue pour pouvoir graver"
        }
        if deviceManager.selectedDevice == nil {
            return "Aucun graveur sélectionné"
        }
        if !burnManager.missingFiles.isEmpty {
            return "Des fichiers référencés par le CUE sont manquants"
        }
        return ""
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // File Selection
                fileSelectionSection

                // Track Info
                if let cueFile = burnManager.cueFile {
                    trackInfoSection(cueFile)
                }

                // Burn Settings
                settingsSection

                // Progress
                if burnManager.isRunning || !burnManager.progress.phase.isActive && burnManager.progress.phase != .idle {
                    progressSection
                }

                // Actions
                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Gravure")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    showLog.toggle()
                } label: {
                    Image(systemName: "terminal")
                }
                .help("Afficher le log")
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
            LogSheetView(title: "Log cdrdao", log: burnManager.log)
        }
        .focusedSceneValue(\.showLog, $showLog)
        .focusedSceneValue(\.burnAction, { startBurn(simulate: false) })
        .focusedSceneValue(\.simulateAction, { startBurn(simulate: true) })
        .focusedSceneValue(\.cancelAction, { burnManager.cancel() })
        .focusedSceneValue(\.openCueAction, { showFilePicker = true })
        .focusedSceneValue(\.canBurn, canStartBurn)
        .focusedSceneValue(\.isRunning, burnManager.isRunning)
    }

    // MARK: - File Selection

    private var fileSelectionSection: some View {
        SectionContainer(title: "Fichier source", systemImage: "doc.badge.gearshape") {
            VStack(spacing: 16) {
                if let cueFile = burnManager.cueFile {
                    // Fichier sélectionné
                    HStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.title2)
                            .foregroundStyle(.orange)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(cueFile.name)
                                .font(.headline)
                            Text("\(cueFile.trackCount) piste(s) — \(String(format: "%.1f", cueFile.totalSizeMB)) Mo")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Changer") {
                            showFilePicker = true
                        }
                    }
                    .padding(8)

                    if !burnManager.missingFiles.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Fichiers manquants", systemImage: "exclamationmark.triangle.fill")
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
                    // Aucun fichier
                    VStack(spacing: 12) {
                        Image(systemName: "opticaldisc")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("Sélectionne un fichier .cue")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Ou glisse-dépose un fichier ici")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Button("Ouvrir un fichier .cue") {
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
        SectionContainer(title: "Pistes (\(cueFile.dataTrackCount) data, \(cueFile.audioTrackCount) audio)", systemImage: "music.note.list") {
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
                    title: "Vitesse",
                    systemImage: "speedometer",
                    description: "Une vitesse basse réduit le risque d'erreurs et améliore la qualité de la gravure."
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
                    title: "Mode RAW",
                    systemImage: "waveform",
                    description: "Nécessaire pour graver certains disques de jeux vidéo. Copie les données telles quelles, sans modification."
                ) {
                    Toggle("", isOn: $burnManager.settings.rawMode)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Inverser les données audio",
                    systemImage: "arrow.left.arrow.right",
                    description: "À activer si le son est déformé ou inaudible après la gravure."
                ) {
                    Toggle("", isOn: $burnManager.settings.swapAudio)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Éjecter après la gravure",
                    systemImage: "eject",
                    description: "Le disque est automatiquement éjecté une fois la gravure terminée."
                ) {
                    Toggle("", isOn: $burnManager.settings.eject)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Overburn",
                    systemImage: "exclamationmark.triangle",
                    description: "Permet de graver au-delà de la capacité prévue du disque. Ne fonctionne pas avec tous les graveurs."
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
        SectionContainer(title: "Progression", systemImage: "flame") {
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

    private var actionsSection: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                if burnManager.isRunning {
                    Button(role: .destructive) {
                        burnManager.cancel()
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        startBurn(simulate: false)
                    } label: {
                        Label("Graver", systemImage: "flame")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canStartBurn)
                    .controlSize(.large)
                    .help(burnHelpString)

                    Button {
                        startBurn(simulate: true)
                    } label: {
                        Label("Simuler", systemImage: "play.slash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(!canStartBurn)
                    .controlSize(.large)
                    .help(burnHelpString)
                }
            }
        }
    }

    // MARK: - Burn Actions

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
