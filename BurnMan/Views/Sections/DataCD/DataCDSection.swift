import SwiftUI
import UniformTypeIdentifiers

struct DataCDSection: View {
    @Environment(DataDiscManager.self) private var dataDiscManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 20) {
            DataFilesListView(onOpenFilePicker: { openFilePicker() })

            if !dataDiscManager.files.isEmpty {
                DataCapacityView()
            }

            DataCDSettingsView()
        }
        .sheet(isPresented: $showLog) {
            LogSheetView(title: "Data CD Log", log: dataDiscManager.log)
        }
        .bindTaskContext(
            canExecute: dataDiscManager.canBurn && deviceManager.selectedDevice != nil,
            isRunning: dataDiscManager.isRunning
        ) {
            TaskBinding(
                canExecute: dataDiscManager.canBurn && deviceManager.selectedDevice != nil,
                isRunning: dataDiscManager.isRunning,
                onExecute: { startPipeline(simulate: false) },
                onSimulate: { startPipeline(simulate: true) },
                onCancel: { dataDiscManager.cancel() },
                onAddFiles: { openFilePicker() }
            )
        }
        .task(id: dataDiscManager.isRunning) {
            if dataDiscManager.isRunning {
                while !Task.isCancelled {
                    syncProgressToToolbar()
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            // Final sync captures terminal states (.completed, .failed)
            syncProgressToToolbar()
        }
    }

    // MARK: - Progress Sync

    private func syncProgressToToolbar() {
        let progress = dataDiscManager.progress

        // Overall progress (0.0–1.0)
        taskContext.progress = progress.overallPercentage / 100.0

        // Elapsed time
        taskContext.elapsedFormatted = progress.elapsedFormatted

        // Detail data for popover
        taskContext.detailPayload = .dataCDBurn(progress: progress)

        // Status text
        switch progress.phase {
        case .creatingISO:
            let pct = Int(progress.isoPercent)
            taskContext.statusText = "Creating ISO… \(pct)%"
        case .burning:
            let pct = Int(progress.burnPercent)
            if let speed = progress.writeSpeed {
                taskContext.statusText = "Burning… \(pct)% (\(speed))"
            } else {
                taskContext.statusText = "Burning…"
            }
        case .verifying:
            taskContext.statusText = "Verifying…"
        case .validating:
            taskContext.statusText = "Validating…"
        case .cleaningUp:
            taskContext.statusText = "Cleaning up…"
        default:
            taskContext.statusText = ""
        }

        // Terminal states
        switch progress.phase {
        case .completed:
            taskContext.isRunning = false
            let label = progress.isSimulation ? "Simulation" : "Data CD burned"
            taskContext.result = .completed("\(label) in \(progress.elapsedFormatted)")
            taskContext.warnings = progress.warnings
            taskContext.onDismissResult = {
                dataDiscManager.progress = DataCDProgress()
                taskContext.clearResult()
            }
            taskContext.onRetry = nil
        case .failed(let message):
            taskContext.isRunning = false
            taskContext.result = .failed(message)
            taskContext.warnings = progress.warnings
            taskContext.onDismissResult = {
                dataDiscManager.progress = DataCDProgress()
                taskContext.clearResult()
            }
            taskContext.onRetry = {
                taskContext.clearResult()
                startPipeline(simulate: dataDiscManager.settings.simulate)
            }
        default:
            break
        }
    }

    // MARK: - Actions

    private func startPipeline(simulate: Bool) {
        guard let device = deviceManager.selectedDevice else { return }
        dataDiscManager.settings.simulate = simulate
        dataDiscManager.targetMedia = .cd
        Task {
            await dataDiscManager.startBurnCD(device: device)
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
}
