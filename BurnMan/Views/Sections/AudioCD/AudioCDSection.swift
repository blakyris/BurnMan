import os
import SwiftUI
import UniformTypeIdentifiers

struct AudioCDSection: View {
    @Environment(AudioCDManager.self) private var audioCDManager
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(ActiveTaskContext.self) private var taskContext
    @Environment(MediaPlayerService.self) private var mediaPlayer
    @State private var showLog = false
    @State private var showFilePicker = false

    var body: some View {
        VStack(spacing: 20) {
            AudioTracksListView(onOpenFilePicker: { openFilePicker() })

            if !audioCDManager.tracks.isEmpty {
                AudioCapacityView()
                AudioCDTextEditor()
            }

            AudioCDSettingsView()
        }
        .sheet(isPresented: $showLog) {
            LogSheetView(title: "Audio CD Log", log: audioCDManager.log)
        }
        .bindTaskContext(
            canExecute: audioCDManager.canBurn && deviceManager.selectedDevice != nil,
            isRunning: audioCDManager.isRunning
        ) {
            TaskBinding(
                canExecute: audioCDManager.canBurn && deviceManager.selectedDevice != nil,
                isRunning: audioCDManager.isRunning,
                onExecute: { startPipeline(simulate: false) },
                onSimulate: { startPipeline(simulate: true) },
                onCancel: { audioCDManager.cancel() },
                onAddFiles: { openFilePicker() }
            )
        }
        .task(id: audioCDManager.isRunning) {
            if audioCDManager.isRunning {
                while !Task.isCancelled {
                    syncProgressToToolbar()
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            // Final sync captures terminal states (.completed, .failed)
            syncProgressToToolbar()
        }
        .onChange(of: showFilePicker) {
            Logger.audioCD.debug("showFilePicker changed to: \(showFilePicker)")
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: {
                var types: [UTType] = [.audio, .mp3, .wav, .aiff]
                if let flac = UTType(filenameExtension: "flac") {
                    types.append(flac)
                }
                return types
            }(),
            allowsMultipleSelection: true
        ) { result in
            Logger.audioCD.debug("fileImporter result: \(String(describing: result))")
            switch result {
            case .success(let urls):
                Logger.audioCD.debug("Selected \(urls.count) file(s)")
                Task {
                    await audioCDManager.addFiles(urls: urls)
                    Logger.audioCD.debug("addFiles completed, track count: \(audioCDManager.tracks.count)")
                }
            case .failure(let error):
                Logger.audioCD.error("fileImporter error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Progress Sync

    private func syncProgressToToolbar() {
        let progress = audioCDManager.progress

        // Overall progress (0.0–1.0)
        taskContext.progress = progress.overallPercentage / 100.0

        // MB counters
        taskContext.currentMB = progress.currentMB
        taskContext.totalMB = progress.totalMB

        // Elapsed time
        taskContext.elapsedFormatted = progress.elapsedFormatted

        // Detail data for popover
        taskContext.detailPayload = .audioCDBurn(progress: progress, tracks: audioCDManager.tracks)

        // Status text
        switch progress.pipelinePhase {
        case .burning:
            taskContext.statusText = "Burning…"
        case .converting(let cur, let tot):
            taskContext.statusText = "Converting \(cur)/\(tot)…"
        case .validating:
            taskContext.statusText = "Validating…"
        case .generatingTOC:
            taskContext.statusText = "Generating TOC…"
        case .cleaningUp:
            taskContext.statusText = "Cleaning up…"
        default:
            taskContext.statusText = ""
        }

        // Terminal states
        switch progress.pipelinePhase {
        case .completed:
            taskContext.isRunning = false
            taskContext.result = .completed("Audio CD burned in \(progress.elapsedFormatted)")
            taskContext.warnings = progress.warnings
            taskContext.onDismissResult = {
                audioCDManager.progress = AudioCDProgress()
                taskContext.clearResult()
            }
            taskContext.onRetry = nil
        case .failed(let message):
            taskContext.isRunning = false
            taskContext.result = .failed(message)
            taskContext.warnings = progress.warnings
            taskContext.onDismissResult = {
                audioCDManager.progress = AudioCDProgress()
                taskContext.clearResult()
            }
            taskContext.onRetry = {
                taskContext.clearResult()
                startPipeline(simulate: audioCDManager.settings.simulate)
            }
        default:
            break
        }
    }

    // MARK: - Actions

    private func startPipeline(simulate: Bool) {
        guard let device = deviceManager.selectedDevice else { return }
        mediaPlayer.stop()
        audioCDManager.settings.simulate = simulate
        Task {
            await audioCDManager.startPipeline(device: device)
        }
    }

    private func openFilePicker() {
        Logger.audioCD.debug("openFilePicker called")
        showFilePicker = true
    }
}
