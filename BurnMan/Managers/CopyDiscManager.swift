import DiscRecording
import Foundation

/// Manages disc-to-disc and disc-to-image copy operations.
@MainActor
@Observable
class CopyDiscManager: Loggable {
    // MARK: - State

    var state: PipelineState = .idle
    var error: String?
    var log: [String] = []
    var copyMode: CopyMode = .discToDisc
    var onTheFly = false

    // MARK: - Services

    let discBurningService: DiscBurningService
    let discImageService: DiscImageService
    let decryptionService: DecryptionService

    // MARK: - Private

    private var cancelled = false
    private var tempDirectory: URL?
    private let logPoller = LogFilePoller()

    // MARK: - Init

    init(
        discBurningService: DiscBurningService,
        discImageService: DiscImageService,
        decryptionService: DecryptionService
    ) {
        self.discBurningService = discBurningService
        self.discImageService = discImageService
        self.decryptionService = decryptionService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - Content State

    var hasContent: Bool { state != .idle }

    func reset() {
        cancel()
        state = .idle
        error = nil
        log = []
    }

    // MARK: - Copy CD (disc-to-disc)

    /// Copies a CD using cdrdao copy (requires two optical drives).
    func copyCD(sourceDevice: String, destDevice: String) async {
        cancelled = false
        error = nil
        log = []
        state = .copying

        appendLog("Copying CD...")
        let (output, exitCode) = await discBurningService.copyDisc(
            sourceDevice: sourceDevice,
            destDevice: destDevice,
            onTheFly: onTheFly
        )

        if !output.isEmpty {
            appendLog(output)
        }

        if exitCode == 0 {
            appendLog("Copy completed.")
            state = .finished
        } else {
            fail("CD copy error (code \(exitCode))")
        }
    }

    // MARK: - Copy DVD/BD (disc → ISO → burn)

    /// Copies a DVD or Blu-ray by reading to a temp ISO then burning it.
    func copyDVD(
        sourceBsdName: String?,
        destDevice: String,
        mediaCategory: TargetMedia,
        encrypted: Bool = false
    ) async {
        cancelled = false
        error = nil
        log = []

        guard let bsd = sourceBsdName else {
            fail("Unable to determine source BSD device.")
            return
        }

        // Step 1: Read to temp ISO
        state = .reading
        appendLog("Reading source disc...")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_Copy_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir

        let isoPath = tempDir.appendingPathComponent("disc_copy.iso").path
        let logPath = HelperLogPath.discCopy
        FileManager.default.createFile(atPath: logPath, contents: nil)
        startLogPolling(logPath: logPath)

        let readExitCode: Int32

        if encrypted {
            guard decryptionService.isDvdCssAvailable else {
                fail("libdvdcss is not installed. Install it with: brew install libdvdcss")
                stopLogPolling(logPath: logPath)
                return
            }

            readExitCode = await discImageService.readEncryptedDVD(
                bsdName: bsd,
                outputPath: isoPath
            ) { [weak self] line in
                self?.appendLog(line)
            }
        } else {
            let (exitCode, errorMessage) = await discImageService.readToISO(
                bsdName: bsd,
                outputPath: isoPath,
                logPath: logPath
            )
            readExitCode = exitCode
            if !errorMessage.isEmpty {
                appendLog(errorMessage)
            }
        }

        guard readExitCode == 0 else {
            fail("Source disc read error (code \(readExitCode))")
            stopLogPolling(logPath: logPath)
            cleanup()
            return
        }

        guard !cancelled else {
            stopLogPolling(logPath: logPath)
            cleanup()
            return
        }

        // Step 2: Burn ISO to destination
        state = .burning
        appendLog("Burning image to destination disc...")

        stopLogPolling(logPath: logPath)

        guard mediaCategory != .cd else {
            fail("Use direct copy for CDs.")
            cleanup()
            return
        }

        // Burn via DiscRecording
        guard let drDevice = discBurningService.findDevice(bsdName: destDevice)
                ?? discBurningService.allDevices().first else {
            fail("Unable to find DiscRecording drive.")
            cleanup()
            return
        }

        nonisolated(unsafe) let safeDevice = drDevice
        let result = await discBurningService.burnISO(
            isoPath: isoPath,
            device: safeDevice,
            options: BurnOptions(eject: true)
        )

        if result.success {
            appendLog("Copy completed successfully.")
            state = .finished
        } else {
            fail(result.errorMessage)
        }

        cleanup()
    }

    func cancel() {
        cancelled = true
        discImageService.cancel()
        discBurningService.cancelBurn()
        discBurningService.cancelCdrdao()
        state = .failed
        error = "Cancelled by user"
        cleanup()
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
        appendLog("Error: \(message)")
    }

    private func cleanup() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
    }

    // MARK: - Log Polling

    private func startLogPolling(logPath: String) {
        logPoller.start(logPath: logPath, interval: .milliseconds(300)) { [weak self] lines in
            for line in lines { self?.appendLog(line) }
        }
    }

    private func stopLogPolling(logPath: String) {
        logPoller.stop(logPath: logPath) { [weak self] lines in
            for line in lines { self?.appendLog(line) }
        }
    }
}
