import SwiftUI
import UniformTypeIdentifiers

struct DataDiscView: View {
    @Environment(DataDiscManager.self) private var dataDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @State private var isDragTargeted = false

    private var canStartBurn: Bool {
        !dataDiscManager.files.isEmpty && deviceManager.selectedDevice != nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                filesSection

                if !dataDiscManager.files.isEmpty {
                    sizeSection
                }

                settingsSection

                if dataDiscManager.state != .idle {
                    statusSection
                }

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Disque de données")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - Files

    private var filesSection: some View {
        SectionContainer(title: "Fichiers", systemImage: "folder.fill") {
            if dataDiscManager.files.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)

                    Text("Ajoute des fichiers ou dossiers")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Text("Glisse-dépose des fichiers ici")
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
                    ForEach(dataDiscManager.files) { file in
                        HStack(spacing: 10) {
                            Image(systemName: file.icon)
                                .foregroundStyle(.secondary)

                            Text(file.name)
                                .font(.subheadline)
                                .lineLimit(1)

                            Spacer()

                            Text(String(format: "%.1f Mo", file.fileSizeMB))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)

                        if file.id != dataDiscManager.files.last?.id {
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

                    Text("\(dataDiscManager.files.count) fichier(s)")
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

    // MARK: - Size

    private var sizeSection: some View {
        SectionContainer(title: "Espace", systemImage: "chart.bar") {
            HStack {
                Text(String(format: "%.1f Mo", dataDiscManager.totalSizeMB))
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.medium)

                Spacer()

                Text("\(dataDiscManager.files.count) fichier(s)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var dataDiscManager = dataDiscManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Nom du disque",
                    systemImage: "textformat",
                    description: "Le nom qui apparaitra sur le disque."
                ) {
                    TextField("", text: $dataDiscManager.discLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                SettingRow(
                    title: "Support cible",
                    systemImage: "opticaldisc",
                    description: "Choisissez le type de disque vierge."
                ) {
                    Picker("", selection: $dataDiscManager.targetMedia) {
                        Text("CD").tag(TargetMedia.cd)
                        Text("DVD").tag(TargetMedia.dvd)
                        Text("Blu-ray").tag(TargetMedia.bluray)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch dataDiscManager.state {
                case .burning:
                    ProgressView()
                        .controlSize(.small)
                    Text("Gravure en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Gravure terminée")
                case .failed:
                    if let error = dataDiscManager.error {
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
                if dataDiscManager.isRunning {
                    Button(role: .destructive) {
                        dataDiscManager.cancel()
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
            await dataDiscManager.startBurn(device: device.path)
        }
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.item]

        panel.begin { response in
            if response == .OK {
                dataDiscManager.addFiles(urls: panel.urls)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    dataDiscManager.addFiles(urls: [url])
                }
            }
            handled = true
        }
        return handled
    }
}
