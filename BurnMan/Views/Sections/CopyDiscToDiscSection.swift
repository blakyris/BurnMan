import SwiftUI

struct CopyDiscToDiscSection: View {
    @Environment(CopyDiscManager.self) private var copyDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

    @State private var mediaCategory: TargetMedia = .cd
    @State private var isEncrypted = false

    var body: some View {
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
        }
        .onAppear { updateTaskContext() }
        .onChange(of: copyDiscManager.isRunning) { updateTaskContext() }
    }

    private func updateTaskContext() {
        let canStart = deviceManager.selectedDevice != nil && !copyDiscManager.isRunning
        taskContext.actionLabel = "Copy"
        taskContext.actionIcon = "doc.on.doc"
        taskContext.canExecute = canStart
        taskContext.isRunning = copyDiscManager.isRunning
        taskContext.onExecute = { startCopy() }
        taskContext.onSimulate = nil
        taskContext.onCancel = { copyDiscManager.cancel() }
        taskContext.onAddFiles = nil
        taskContext.statusText = copyDiscManager.isRunning ? "Copying disc…" : ""
    }

    // MARK: - Settings

    private var settingsSection: some View {
        @Bindable var copyDiscManager = copyDiscManager

        return SectionContainer(title: "Configuration", systemImage: "doc.on.doc") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Disc Type",
                    systemImage: "opticaldisc",
                    description: "The type of disc to copy."
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
                            Text("The disc will be read to a temporary ISO image, then burned to the blank disc.")
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

        return SectionContainer(title: "CD Options", systemImage: "opticaldisc") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "On-the-fly copy",
                    systemImage: "bolt",
                    description: "Direct copy without intermediate image (requires two drives)."
                ) {
                    Toggle("", isOn: $copyDiscManager.onTheFly)
                        .toggleStyle(.switch)
                }

                if deviceManager.devices.count < 2 {
                    HStack {
                        Label {
                            Text("CD copying requires two optical drives. Only one detected.")
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
            SettingRow(
                title: "Encrypted disc (CSS)",
                systemImage: "lock",
                description: decryptionStatusDescription
            ) {
                Toggle("", isOn: $isEncrypted)
                    .toggleStyle(.switch)
            }
        }
    }

    private var decryptionStatusDescription: String {
        if copyDiscManager.decryptionService.isDvdCssAvailable {
            return "libdvdcss detected. Copying encrypted DVDs is possible."
        } else {
            return "libdvdcss not found. Install it: brew install libdvdcss"
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        SectionContainer(title: "Progress", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch copyDiscManager.state {
                case .reading:
                    ProgressView()
                        .controlSize(.small)
                    Text("Reading source disc…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .copying:
                    ProgressView()
                        .controlSize(.small)
                    Text("Copying…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .burning:
                    ProgressView()
                        .controlSize(.small)
                    Text("Burning…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Copy complete")
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

    private func startCopy() {
        guard let sourceDevice = deviceManager.selectedDevice else { return }

        Task {
            switch mediaCategory {
            case .cd:
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
