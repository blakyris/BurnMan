import SwiftUI

struct EraseDiscSection: View {
    @Environment(EraseDiscManager.self) private var eraseDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

    @State private var selectedMediaType: MediaType = .cdRW

    private var canErase: Bool {
        deviceManager.selectedDevice != nil && !eraseDiscManager.isRunning
    }

    var body: some View {
        VStack(spacing: 20) {
            infoSection
            settingsSection

            if eraseDiscManager.state != .idle {
                statusSection
            }
        }
        .onAppear { updateTaskContext() }
        .onChange(of: eraseDiscManager.isRunning) { updateTaskContext() }
    }

    private func updateTaskContext() {
        taskContext.actionLabel = "Erase"
        taskContext.actionIcon = "eraser"
        taskContext.canExecute = canErase
        taskContext.isRunning = eraseDiscManager.isRunning
        taskContext.onExecute = { startErase() }
        taskContext.onSimulate = nil
        taskContext.onCancel = { eraseDiscManager.cancel() }
        taskContext.onAddFiles = nil
        taskContext.statusText = eraseDiscManager.isRunning ? "Erasing disc…" : ""
    }

    // MARK: - Info

    private var infoSection: some View {
        SectionContainer(title: "Information", systemImage: "info.circle") {
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    Text("This operation erases all data on the disc.")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.subheadline)

                Text("Only rewritable discs (CD-RW, DVD±RW, BD-RE) can be erased.")
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
                    title: "Disc Type",
                    systemImage: "opticaldisc",
                    description: "Select the type of disc inserted."
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
                        title: "Erase Mode",
                        systemImage: "eraser",
                        description: "Full: erases everything. Fast: erases TOC only."
                    ) {
                        Picker("", selection: $eraseDiscManager.blankMode) {
                            Text("Full").tag(BlankMode.full)
                            Text("Fast").tag(BlankMode.minimal)
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
        SectionContainer(title: "Progress", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch eraseDiscManager.state {
                case .erasing:
                    ProgressView()
                        .controlSize(.small)
                    Text("Erasing…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .finished:
                    CompletionBadge(message: "Disc erased successfully")
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

    private func startErase() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await eraseDiscManager.erase(device: device.path, mediaType: selectedMediaType)
        }
    }
}
