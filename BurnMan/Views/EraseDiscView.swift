import SwiftUI

struct EraseDiscView: View {
    @Environment(EraseDiscManager.self) private var eraseDiscManager
    @Environment(DeviceManager.self) private var deviceManager

    /// Detected media type for the selected device (simplified: user picks manually).
    @State private var selectedMediaType: MediaType = .cdRW

    private var canErase: Bool {
        deviceManager.selectedDevice != nil && !eraseDiscManager.isRunning
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                infoSection
                settingsSection

                if eraseDiscManager.state != .idle {
                    statusSection
                }

                actionsSection
            }
            .padding(24)
        }
        .navigationTitle("Effacer un disque")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                DevicePickerView()
            }
        }
    }

    // MARK: - Info

    private var infoSection: some View {
        SectionContainer(title: "Information", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("Cette opération efface toutes les données du disque.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)

                Text("Seuls les disques réinscriptibles (CD-RW, DVD±RW, BD-RE) peuvent être effacés.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var eraseDiscManager = eraseDiscManager

        return SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Type de disque",
                    systemImage: "opticaldisc",
                    description: "Sélectionnez le type du disque inséré."
                ) {
                    Picker("", selection: $selectedMediaType) {
                        Text("CD-RW").tag(MediaType.cdRW)
                        Text("DVD+RW").tag(MediaType.dvdPlusRW)
                        Text("DVD-RW").tag(MediaType.dvdMinusRW)
                        Text("BD-RE").tag(MediaType.bdRE)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }

                if selectedMediaType == .cdRW {
                    SettingRow(
                        title: "Mode d'effacement",
                        systemImage: "eraser",
                        description: "Complet : efface tout. Rapide : efface le TOC uniquement."
                    ) {
                        Picker("", selection: $eraseDiscManager.blankMode) {
                            Text("Complet").tag(BlankMode.full)
                            Text("Rapide").tag(BlankMode.minimal)
                        }
                        .pickerStyle(.segmented)
                        .fixedSize()
                    }
                }
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progression", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch eraseDiscManager.state {
                case .erasing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Effacement en cours...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Disque effacé avec succès")
                case .failed:
                    if let error = eraseDiscManager.error {
                        ErrorBadge(message: error)
                    }
                default:
                    ProgressView()
                        .controlSize(.small)
                    Text(eraseDiscManager.state.displayName)
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
                if eraseDiscManager.isRunning {
                    Button(role: .destructive) {
                        eraseDiscManager.cancel()
                    } label: {
                        Label("Annuler", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.glass)
                } else {
                    Button {
                        startErase()
                    } label: {
                        Label("Effacer le disque", systemImage: "eraser")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canErase)
                    .controlSize(.large)
                }
            }
        }
    }

    // MARK: - Actions

    private func startErase() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await eraseDiscManager.erase(device: device.path, mediaType: selectedMediaType)
        }
    }
}
