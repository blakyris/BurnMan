import SwiftUI

struct EraseDiscSection: View {
    @Environment(EraseDiscManager.self) private var eraseDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext

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
        .bindTaskContext(id: eraseDiscManager.isRunning) {
            TaskBinding(
                actionLabel: "Erase",
                actionIcon: "eraser",
                canExecute: canErase,
                isRunning: eraseDiscManager.isRunning,
                onExecute: { startErase() },
                onCancel: { eraseDiscManager.cancel() },
                statusText: eraseDiscManager.isRunning ? "Erasing disc…" : ""
            )
        }
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

    // MARK: - Status

    private var statusSection: some View {
        PipelineStatusView(
            state: eraseDiscManager.state,
            error: eraseDiscManager.error,
            completionMessage: "Disc erased successfully"
        )
    }

    // MARK: - Actions

    private func startErase() {
        guard let device = deviceManager.selectedDevice else { return }
        Task {
            await eraseDiscManager.erase(device: device)
        }
    }
}
