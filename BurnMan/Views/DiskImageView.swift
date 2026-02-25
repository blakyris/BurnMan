import SwiftUI

struct DiskImageView: View {
    @Environment(DiskImageManager.self) private var diskImageManager
    @Environment(DeviceManager.self) private var deviceManager

    @State private var mediaCategory: TargetMedia = .dvd
    @State private var isEncrypted = false

    private var canCreate: Bool {
        deviceManager.selectedDevice != nil
            && diskImageManager.outputURL != nil
            && !diskImageManager.isRunning
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                outputSection
                settingsSection

                if diskImageManager.state != .idle {
                    statusSection
                }

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Créer une image disque")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        @Bindable var diskImageManager = diskImageManager

        return SectionContainer(title: "Fichier de sortie", systemImage: "doc.badge.arrow.up") {
            VStack(spacing: 12) {
                if let url = diskImageManager.outputURL {
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
                        diskImageManager.outputURL == nil ? "Choisir l'emplacement" : "Modifier",
                        systemImage: "folder"
                    )
                    .font(.caption)
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var diskImageManager = diskImageManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Type de disque source",
                    systemImage: "opticaldisc",
                    description: "Le type du disque inséré dans le lecteur."
                ) {
                    Picker("", selection: $mediaCategory) {
                        Text("CD").tag(TargetMedia.cd)
                        Text("DVD").tag(TargetMedia.dvd)
                        Text("Blu-ray").tag(TargetMedia.bluray)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if mediaCategory == .cd {
                    SettingRow(
                        title: "Format de sortie",
                        systemImage: "doc.zipper",
                        description: "ISO pour un fichier unique, CUE/BIN pour une copie fidèle."
                    ) {
                        Picker("", selection: $diskImageManager.outputFormat) {
                            Text("ISO").tag(ImageOutputFormat.iso)
                            Text("CUE/BIN").tag(ImageOutputFormat.cueBin)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }

                if mediaCategory == .dvd {
                    SettingRow(
                        title: "Disque chiffré (CSS)",
                        systemImage: "lock.shield",
                        description: decryptionStatusDescription
                    ) {
                        Toggle("", isOn: $isEncrypted)
                            .toggleStyle(.switch)
                    }
                }
            }
        }
    }

    private var decryptionStatusDescription: String {
        if diskImageManager.decryptionService.isDvdCssAvailable {
            return "libdvdcss détecté. La lecture de DVD protégés est possible."
        } else {
            return "libdvdcss non trouvé. Installez-le : brew install libdvdcss"
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch diskImageManager.state {
                case .reading:
                    ProgressView()
                        .controlSize(.small)
                    Text("Lecture du disque en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Image disque créée")
                case .failed:
                    if let error = diskImageManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text(diskImageManager.state.displayName)
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
                if diskImageManager.isRunning {
                    Button(role: .destructive) {
                        diskImageManager.cancel()
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        startCreation()
                    } label: {
                        Label("Créer l'image", systemImage: "opticaldisc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canCreate)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Actions

    private func startCreation() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await diskImageManager.createImage(
                device: device.path,
                bsdName: device.bsdName,
                mediaCategory: mediaCategory,
                encrypted: isEncrypted
            )
        }
    }

    private func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.title = "Enregistrer l'image disque"
        panel.nameFieldStringValue = "disc_image"

        switch diskImageManager.outputFormat {
        case .iso:
            panel.allowedContentTypes = [.init(filenameExtension: "iso")!]
            panel.nameFieldStringValue += ".iso"
        case .cueBin:
            panel.allowedContentTypes = [.init(filenameExtension: "bin")!]
            panel.nameFieldStringValue += ".bin"
        }

        panel.begin { response in
            if response == .OK, let url = panel.url {
                diskImageManager.outputURL = url
            }
        }
    }
}
