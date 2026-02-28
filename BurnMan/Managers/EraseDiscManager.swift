import DiscRecording
import Foundation

/// Manages disc erasing for CD-RW, DVD±RW, and BD-RE using DiscRecording.
@MainActor
@Observable
class EraseDiscManager: Loggable {
    // MARK: - State

    var state: PipelineState = .idle
    var error: String?
    var blankMode: BlankMode = .full
    var log: [String] = []

    // MARK: - Services

    let discBurningService: DiscBurningService

    // MARK: - Init

    init(discBurningService: DiscBurningService) {
        self.discBurningService = discBurningService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - Erase

    /// Erases a rewritable disc using DiscRecording (no root required).
    func erase(device: DiscDevice) async {
        state = .erasing
        error = nil
        log = []

        appendLog("Erasing disc...")

        guard let drDevice = discBurningService.findDevice(bsdName: device.bsdName ?? "")
                ?? discBurningService.allDevices().first else {
            fail("Unable to find DiscRecording drive.")
            return
        }

        discBurningService.onEraseStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.appendLog("Erasing: \(Int(status.percentComplete))%")
            }
        }

        nonisolated(unsafe) let device = drDevice
        let result = await discBurningService.erase(
            device: device,
            quick: blankMode == .minimal
        )

        discBurningService.onEraseStatusChanged = nil

        if result.success {
            appendLog("Erase completed.")
            state = .finished
        } else {
            fail(result.errorMessage)
        }
    }

    func cancel() {
        discBurningService.cancelErase()
        state = .failed
        error = "Cancelled by user"
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
        appendLog("Error: \(message)")
    }

}
