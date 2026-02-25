import Foundation

/// Manages disc image creation from physical discs and image format conversion.
/// Handles: disc → ISO, disc → CUE/BIN, and image format conversion.
@MainActor
@Observable
class DiskImageManager {
    // MARK: - State

    var state: PipelineState = .idle
    var error: String?
    var log: [String] = []
    var outputFormat: ImageOutputFormat = .iso
    var outputURL: URL?

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let discImageService: DiscImageService
    let decryptionService: DecryptionService

    // MARK: - Private

    private var cancelled = false
    private var logPollTask: Task<Void, Never>?
    private var lastLogOffset: UInt64 = 0

    // MARK: - Init

    init(
        compactDiscService: CompactDiscService,
        discImageService: DiscImageService,
        decryptionService: DecryptionService
    ) {
        self.compactDiscService = compactDiscService
        self.discImageService = discImageService
        self.decryptionService = decryptionService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - Create Image from Disc

    /// Creates a disc image from a physical disc.
    /// - Parameters:
    ///   - device: Device path for cdrdao operations
    ///   - bsdName: BSD name (e.g. "disk4") for dd/ISO operations
    ///   - mediaCategory: The type of disc (CD, DVD, BD)
    ///   - encrypted: Whether the disc uses CSS encryption (DVD only)
    func createImage(
        device: String,
        bsdName: String?,
        mediaCategory: TargetMedia,
        encrypted: Bool = false
    ) async {
        cancelled = false
        error = nil
        log = []

        guard let output = outputURL else {
            fail("Aucun emplacement de sortie sélectionné.")
            return
        }

        state = .reading
        appendLog("Lecture du disque...")

        let logPath = "/tmp/burnman_image_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        startLogPolling(logPath: logPath)

        switch mediaCategory {
        case .cd:
            await createCDImage(device: device, output: output, logPath: logPath)

        case .dvd, .bluray:
            if encrypted {
                await createEncryptedDVDImage(bsdName: bsdName, output: output)
            } else {
                await createISOImage(bsdName: bsdName, output: output, logPath: logPath)
            }
        }

        stopLogPolling(logPath: logPath)
    }

    func cancel() {
        cancelled = true
        discImageService.cancel()
        Task { @MainActor in
            _ = await compactDiscService.cancel()
        }
        state = .failed
        error = "Annulé par l'utilisateur"
    }

    // MARK: - Private Pipelines

    private func createCDImage(device: String, output: URL, logPath: String) async {
        if outputFormat == .cueBin {
            // cdrdao read-cd produces TOC + BIN
            let tocPath = output.deletingPathExtension().appendingPathExtension("toc").path
            let (_, exitCode) = await compactDiscService.readCD(
                device: device,
                outputFile: tocPath
            )
            if exitCode == 0 {
                appendLog("Image CUE/BIN créée avec succès.")
                state = .finished
            } else {
                fail("Erreur de lecture du CD (code \(exitCode))")
            }
        } else {
            // ISO from CD — read via cdrdao then convert, or use dd
            let (_, exitCode) = await compactDiscService.readCD(
                device: device,
                outputFile: output.path
            )
            if exitCode == 0 {
                appendLog("Image ISO créée avec succès.")
                state = .finished
            } else {
                fail("Erreur de lecture du CD (code \(exitCode))")
            }
        }
    }

    private func createISOImage(bsdName: String?, output: URL, logPath: String) async {
        guard let bsd = bsdName else {
            fail("Impossible de déterminer le périphérique BSD.")
            return
        }

        appendLog("Lecture du disque via dd (\(bsd))...")
        let (exitCode, errorMessage) = await discImageService.readToISO(
            bsdName: bsd,
            outputPath: output.path,
            logPath: logPath
        )

        if exitCode == 0 {
            appendLog("Image ISO créée avec succès.")
            state = .finished
        } else {
            fail(errorMessage.isEmpty ? "Erreur de lecture (code \(exitCode))" : errorMessage)
        }
    }

    private func createEncryptedDVDImage(bsdName: String?, output: URL) async {
        guard let bsd = bsdName else {
            fail("Impossible de déterminer le périphérique BSD.")
            return
        }

        guard decryptionService.isDvdCssAvailable else {
            fail("libdvdcss n'est pas installé. Installez-le avec : brew install libdvdcss")
            return
        }

        appendLog("Lecture du DVD chiffré via ffmpeg (\(bsd))...")
        let exitCode = await discImageService.readEncryptedDVD(
            bsdName: bsd,
            outputPath: output.path
        ) { [weak self] line in
            self?.appendLog(line)
        }

        if exitCode == 0 {
            appendLog("Image créée avec succès.")
            state = .finished
        } else {
            fail("Erreur de lecture du DVD chiffré (code \(exitCode))")
        }
    }

    // MARK: - Helpers

    private func fail(_ message: String) {
        state = .failed
        error = message
        appendLog("Erreur : \(message)")
    }

    func appendLog(_ message: String) {
        log.append(message)
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
