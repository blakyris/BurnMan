import SwiftUI

struct CopyDiscView: View {
    @Environment(CopyDiscManager.self) private var copyDiscManager
    @Environment(DeviceManager.self) private var deviceManager

    @State private var mediaCategory: TargetMedia = .cd
    @State private var isEncrypted = false

    /// For CD disc-to-disc copy with two drives, user picks a destination device.
    @State private var destDeviceIndex: Int = 0

    private var canCopy: Bool {
        deviceManager.selectedDevice != nil && !copyDiscManager.isRunning
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                settingsSection

                if mediaCategory == .cd {
                    cdOptionsSection
                }

                if mediaCategory == .dvd {
                    encryptionSection
                }

                if copyDiscManager.state != .idle {
                    statusSection
                }

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Copier un disque")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var copyDiscManager = copyDiscManager

        return SectionContainer(title: "Configuration", systemImage: "doc.on.doc") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Type de disque",
                    systemImage: "opticaldisc",
                    description: "Le type du disque source à copier."
                ) {
                    Picker("", selection: $mediaCategory) {
                        Text("CD").tag(TargetMedia.cd)
                        Text("DVD").tag(TargetMedia.dvd)
                        Text("Blu-ray").tag(TargetMedia.bluray)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if mediaCategory != .cd {
                    HStack {
                        Label {
                            Text("Le disque sera lu vers une image ISO temporaire, puis gravé sur le disque vierge.")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(.blue)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - CD Options

    private var cdOptionsSection: some View {
        @Bindable var copyDiscManager = copyDiscManager

        return SectionContainer(title: "Options CD", systemImage: "opticaldisc") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Copie à la volée",
                    systemImage: "bolt",
                    description: "Copie directe sans image intermédiaire (nécessite deux lecteurs)."
                ) {
                    Toggle("", isOn: $copyDiscManager.onTheFly)
                        .toggleStyle(.switch)
                }

                if deviceManager.devices.count < 2 {
                    HStack {
                        Label {
                            Text("La copie de CD nécessite deux lecteurs optiques. Un seul détecté.")
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
        }
    }

    // MARK: - Encryption

    private var encryptionSection: some View {
        SectionContainer(title: "Protection", systemImage: "lock.shield") {
            VStack(spacing: 12) {
                SettingRow(
                    title: "Disque chiffré (CSS)",
                    systemImage: "lock",
                    description: decryptionStatusDescription
                ) {
                    Toggle("", isOn: $isEncrypted)
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var decryptionStatusDescription: String {
        if copyDiscManager.decryptionService.isDvdCssAvailable {
            return "libdvdcss détecté. La copie de DVD protégés est possible."
        } else {
            return "libdvdcss non trouvé. Installez-le : brew install libdvdcss"
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch copyDiscManager.state {
                case .reading:
                    ProgressView()
                        .controlSize(.small)
                    Text("Lecture du disque source...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .copying:
                    ProgressView()
                        .controlSize(.small)
                    Text("Copie en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .burning:
                    ProgressView()
                        .controlSize(.small)
                    Text("Gravure en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Copie terminée")
                case .failed:
                    if let error = copyDiscManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text(copyDiscManager.state.displayName)
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
                if copyDiscManager.isRunning {
                    Button(role: .destructive) {
                        copyDiscManager.cancel()
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        startCopy()
                    } label: {
                        Label("Copier", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canCopy)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Actions

    private func startCopy() {
        guard let sourceDevice = deviceManager.selectedDevice else { return }

        Task {
            switch mediaCategory {
            case .cd:
                // For CD, use cdrdao copy (needs two drives)
                let destDevice = deviceManager.devices.count > 1
                    ? deviceManager.devices[1].path
                    : sourceDevice.path
                await copyDiscManager.copyCD(
                    sourceDevice: sourceDevice.path,
                    destDevice: destDevice
                )
            case .dvd, .bluray:
                await copyDiscManager.copyDVD(
                    sourceBsdName: sourceDevice.bsdName,
                    destDevice: sourceDevice.path,
                    mediaCategory: mediaCategory,
                    encrypted: isEncrypted
                )
            }
        }
    }
}
