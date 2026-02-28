import SwiftUI

struct CopyDiscImageSection: View {
    @Environment(DiskImageManager.self) private var diskImageManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

    @State private var mediaCategory: TargetMedia = .dvd
    @State private var isEncrypted = false

    private var canCreate: Bool {
        deviceManager.selectedDevice != nil
            && diskImageManager.outputURL != nil
            && !diskImageManager.isRunning
    }

    var body: some View {
        VStack(spacing: 20) {
            outputSection
            settingsSection

            if diskImageManager.state != .idle {
                statusSection
            }
        }
        .bindTaskContext(canExecute: canCreate, isRunning: diskImageManager.isRunning) {
            TaskBinding(
                actionLabel: "Create",
                actionIcon: "opticaldisc",
                canExecute: canCreate,
                isRunning: diskImageManager.isRunning,
                onExecute: { startCreation() },
                onCancel: { diskImageManager.cancel() },
                statusText: diskImageManager.isRunning ? "Reading disc…" : ""
            )
        }
    }

    // MARK: - Output

    private var outputSection: some View {
        @Bindable var diskImageManager = diskImageManager

        return SectionContainer(title: "Output File", systemImage: "doc.badge.arrow.up") {
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
                        diskImageManager.outputURL == nil ? "Choose Location" : "Change",
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
                    title: "Source Disc Type",
                    systemImage: "opticaldisc",
                    description: "The type of disc inserted in the drive."
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
                        title: "Output Format",
                        systemImage: "doc.zipper",
                        description: "ISO for a single file, CUE/BIN for a faithful copy."
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
                        title: "Encrypted disc (CSS)",
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
            return "libdvdcss detected. Reading encrypted DVDs is possible."
        } else {
            return "libdvdcss not found. Install it: brew install libdvdcss"
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        PipelineStatusView(
            state: diskImageManager.state,
            error: diskImageManager.error,
            completionMessage: "Disc image created"
        )
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
        panel.title = "Save Disc Image"
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
