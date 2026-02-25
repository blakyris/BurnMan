import Foundation

/// Manages disc-to-disc and disc-to-image copy operations.
@MainActor
@Observable
class CopyDiscManager {
    // MARK: - State

    var state: PipelineState = .idle
    var error: String?
    var log: [String] = []
    var copyMode: CopyMode = .discToDisc
    var onTheFly = false

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let discImageService: DiscImageService
    let dvdService: DVDService
    let blurayService: BlurayService
    let decryptionService: DecryptionService

    // MARK: - Private

    private var cancelled = false
    private var tempDirectory: URL?
    private var logPollTask: Task<Void, Never>?
    private var lastLogOffset: UInt64 = 0

    // MARK: - Init

    init(
        compactDiscService: CompactDiscService,
        discImageService: DiscImageService,
        dvdService: DVDService,
        blurayService: BlurayService,
        decryptionService: DecryptionService
    ) {
        self.compactDiscService = compactDiscService
        self.discImageService = discImageService
        self.dvdService = dvdService
        self.blurayService = blurayService
        self.decryptionService = decryptionService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - Copy CD (disc-to-disc)

    /// Copies a CD using cdrdao copy (requires two optical drives).
    func copyCD(sourceDevice: String, destDevice: String) async {
        cancelled = false
        error = nil
        log = []
        state = .copying

        appendLog("Copie du CD...")
        let (output, exitCode) = await compactDiscService.copy(
            sourceDevice: sourceDevice,
            destDevice: destDevice,
            onTheFly: onTheFly
        )

        if !output.isEmpty {
            appendLog(output)
        }

        if exitCode == 0 {
            appendLog("Copie terminée.")
            state = .finished
        } else {
            fail("Erreur de copie du CD (code \(exitCode))")
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
            fail("Impossible de déterminer le périphérique BSD source.")
            return
        }

        // Step 1: Read to temp ISO
        state = .reading
        appendLog("Lecture du disque source...")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_Copy_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir

        let isoPath = tempDir.appendingPathComponent("disc_copy.iso").path
        let logPath = "/tmp/burnman_copy_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        startLogPolling(logPath: logPath)

        let readExitCode: Int32

        if encrypted {
            guard decryptionService.isDvdCssAvailable else {
                fail("libdvdcss n'est pas installé. Installez-le avec : brew install libdvdcss")
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
            fail("Erreur de lecture du disque source (code \(readExitCode))")
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
        appendLog("Gravure de l'image vers le disque destination...")

        let burnExitCode: Int32
        let burnError: String

        switch mediaCategory {
        case .dvd:
            (burnExitCode, burnError) = await dvdService.burn(
                isoPath: isoPath,
                device: destDevice,
                dvdCompat: true,
                logPath: logPath
            )
        case .bluray:
            (burnExitCode, burnError) = await blurayService.burn(
                isoPath: isoPath,
                device: destDevice,
                logPath: logPath
            )
        case .cd:
            // CD copy should use copyCD() instead
            (burnExitCode, burnError) = (-1, "Utilisez la copie directe pour les CD.")
        }

        stopLogPolling(logPath: logPath)

        if burnExitCode == 0 {
            appendLog("Copie terminée avec succès.")
            state = .finished
        } else {
            fail(burnError.isEmpty ? "Erreur de gravure (code \(burnExitCode))" : burnError)
        }

        cleanup()
    }

    func cancel() {
        cancelled = true
        discImageService.cancel()
        Task { @MainActor in
            _ = await compactDiscService.cancel()
            _ = await dvdService.cancel()
        }
        state = .failed
        error = "Annulé par l'utilisateur"
        cleanup()
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
        appendLog("Erreur : \(message)")
    }

    func appendLog(_ message: String) {
        log.append(message)
    }

    private func cleanup() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
    }

    // MARK: - Log Polling

    private func startLogPolling(logPath: String) {
        lastLogOffset = 0
        logPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                readNewLogLines(logPath: logPath)
            }
        }
    }

    private func stopLogPolling(logPath: String) {
        logPollTask?.cancel()
        logPollTask = nil
        readNewLogLines(logPath: logPath)
    }

    private func readNewLogLines(logPath: String) {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastLogOffset)
        let data = handle.readDataToEndOfFile()
        lastLogOffset = handle.offsetInFile

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            appendLog(line)
        }
    }
}
