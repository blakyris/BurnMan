import Foundation

/// Manages disc image creation from physical discs, image format conversion,
/// and burning CUE/BIN images to disc via cdrdao.
@MainActor
@Observable
class DiskImageManager: Loggable {
    // MARK: - Image Creation State

    var state: PipelineState = .idle
    var error: String?
    var log: [String] = []
    var outputFormat: ImageOutputFormat = .iso
    var outputURL: URL?

    // MARK: - Burn State

    var cueFile: CueFile?
    var missingFiles: [String] = []
    var burnSettings = BurnSettings()
    var burnProgress = BurnProgress()

    // MARK: - Services

    let discBurningService: DiscBurningService
    let discImageService: DiscImageService
    let decryptionService: DecryptionService

    // MARK: - Private

    private var cancelled = false
    private let logPoller = LogFilePoller()

    private var burnElapsedTask: Task<Void, Never>?
    private let burnLogPoller = LogFilePoller()
    private var burnStartTime: Date?

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

    var isRunning: Bool { state.isActive || burnProgress.phase.isActive }

    // MARK: - Content State

    var hasContent: Bool { outputURL != nil || state != .idle || cueFile != nil }

    func reset() {
        cancel()
        cancelBurn()
        state = .idle
        error = nil
        log = []
        outputURL = nil
        cueFile = nil
        missingFiles = []
        burnSettings = BurnSettings()
        burnProgress = BurnProgress()
    }

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
            fail("No output location selected.")
            return
        }

        state = .reading
        appendLog("Reading disc...")

        let logPath = HelperLogPath.discImage
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
        discBurningService.cancelCdrdao()
        state = .failed
        error = "Cancelled by user"
    }

    // MARK: - Load CUE File

    func loadCueFile(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let directory = url.deletingLastPathComponent()
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }

        var tracks: [TrackInfo] = []
        var currentFile: String?
        var trackNumber = 0

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.uppercased().hasPrefix("FILE") {
                if let start = trimmed.firstIndex(of: "\""),
                   let end = trimmed[trimmed.index(after: start)...].firstIndex(of: "\"") {
                    currentFile = String(trimmed[trimmed.index(after: start)..<end])
                }
            } else if trimmed.uppercased().hasPrefix("TRACK") {
                trackNumber += 1
                let parts = trimmed.components(separatedBy: " ").filter { !$0.isEmpty }
                let mode: TrackMode
                if parts.count >= 3 {
                    switch parts[2].uppercased() {
                    case "MODE1/2352": mode = .mode1
                    case "MODE2/2352": mode = .mode2
                    case "AUDIO": mode = .audio
                    default: mode = .mode2
                    }
                } else {
                    mode = .mode2
                }

                let fileName = currentFile ?? ""
                let fileURL = directory.appendingPathComponent(fileName)
                let fileSize: UInt64 = (try? FileManager.default
                    .attributesOfItem(atPath: fileURL.path)[.size] as? UInt64) ?? 0

                tracks.append(TrackInfo(
                    number: trackNumber,
                    mode: mode,
                    fileName: fileName,
                    fileURL: fileURL,
                    startSector: 0,
                    endSector: max(0, Int(fileSize) / CdrdaoConfig.sectorSize - 1),
                    sizeBytes: fileSize
                ))
            }
        }

        cueFile = CueFile(url: url, tracks: tracks)

        missingFiles = tracks.compactMap { track in
            guard let fileURL = track.fileURL,
                  !FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return track.fileName
        }
    }

    // MARK: - Start Burn

    func startBurn(device: DiscDevice) async {
        guard cueFile != nil else { return }

        burnProgress = BurnProgress()
        burnProgress.phase = .preparing
        log = []
        burnStartTime = Date()
        startBurnElapsedTimer()

        await runBurnViaHelper(device: device)

        stopBurnTimers()
    }

    // MARK: - Cancel Burn

    func cancelBurn() {
        guard burnProgress.phase.isActive else { return }
        discBurningService.cancelCdrdao()
        burnProgress.phase = .failed("Cancelled by user")
        stopBurnTimers()
    }

    // MARK: - Burn via DiscBurningService

    private func runBurnViaHelper(device: DiscDevice) async {
        let stagingDir = NSTemporaryDirectory() + "cdrburn_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: stagingDir) }

        let stagedCuePath: String
        do {
            stagedCuePath = try stageBurnFiles(to: stagingDir)
            appendLog("Files prepared for burning.")
        } catch {
            burnProgress.phase = .failed("Preparation: \(error.localizedDescription)")
            return
        }

        let options = CdrdaoOptions(
            speed: burnSettings.speed,
            simulate: burnSettings.simulate,
            eject: burnSettings.eject,
            overburn: burnSettings.overburn,
            rawMode: burnSettings.rawMode,
            swapAudio: burnSettings.swapAudio
        )

        appendLog("cdrdao \(burnSettings.simulate ? "simulate" : "write") → \(cueFile?.url.lastPathComponent ?? "?")")

        let logPath = HelperLogPath.imageBurn
        FileManager.default.createFile(atPath: logPath, contents: nil)

        startBurnLogPolling(logPath: logPath)
        burnProgress.phase = .writingTrack(1)
        appendLog("Running via helper (root)...")

        let (exitCode, errorMessage) = await discBurningService.writeCdrdao(
            tocFile: stagedCuePath,
            device: device.path,
            options: options,
            workingDirectory: stagingDir,
            logPath: logPath
        )

        stopBurnLogPolling(flush: true)
        try? FileManager.default.removeItem(atPath: logPath)

        if exitCode == 0 {
            burnProgress.phase = .completed
            appendLog("Burn completed.")
        } else {
            let description = CdrdaoOutputParser.describeExitCode(exitCode, helperMessage: errorMessage)
            burnProgress.phase = .failed(description)
            appendLog("ERROR: \(description)")
        }
    }

    // MARK: - Stage Burn Files

    private func stageBurnFiles(to stagingDir: String) throws -> String {
        guard let cue = cueFile else {
            throw NSError(domain: "DiskImageManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No CUE file loaded"])
        }

        let fm = FileManager.default
        try fm.createDirectory(atPath: stagingDir, withIntermediateDirectories: true)

        let accessing = cue.url.startAccessingSecurityScopedResource()
        defer { if accessing { cue.url.stopAccessingSecurityScopedResource() } }

        var copied = Set<String>()
        for track in cue.tracks {
            guard let fileURL = track.fileURL else { continue }
            let baseName = fileURL.lastPathComponent
            guard !copied.contains(baseName) else { continue }
            copied.insert(baseName)
            try fm.copyItem(atPath: fileURL.path, toPath: "\(stagingDir)/\(baseName)")
        }

        var cueContent = try String(contentsOf: cue.url, encoding: .utf8)
        for track in cue.tracks {
            guard let fileURL = track.fileURL else { continue }
            let baseName = fileURL.lastPathComponent
            if track.fileName != baseName {
                cueContent = cueContent.replacingOccurrences(
                    of: "\"\(track.fileName)\"",
                    with: "\"\(baseName)\""
                )
            }
        }
        let stagedCuePath = "\(stagingDir)/\(cue.url.lastPathComponent)"
        try cueContent.write(toFile: stagedCuePath, atomically: true, encoding: .utf8)

        return stagedCuePath
    }

    // MARK: - Burn Log Polling

    private func startBurnLogPolling(logPath: String) {
        burnLogPoller.start(logPath: logPath) { [weak self] lines in
            for line in lines { self?.parseBurnCdrdaoLine(line) }
        }
    }

    private func stopBurnLogPolling(flush: Bool = false) {
        burnLogPoller.stop(logPath: HelperLogPath.imageBurn) { [weak self] lines in
            guard flush else { return }
            for line in lines { self?.parseBurnCdrdaoLine(line) }
        }
    }

    // MARK: - Parse Burn cdrdao Output

    private func parseBurnCdrdaoLine(_ line: String) {
        appendLog(line)

        CdrdaoOutputParser.applyEvents(
            from: line,
            onPhase: { burnProgress.phase = $0 },
            onProgress: { burnProgress.currentMB = $0; burnProgress.totalMB = $1 },
            onBuffer: { burnProgress.bufferFillFIFO = $0; burnProgress.bufferFillDrive = $1 },
            onTrack: { burnProgress.currentTrack = $0 },
            onStartingWrite: { burnProgress.writeSpeed = $0; burnProgress.isSimulation = $1 },
            onWarning: { burnProgress.warnings.append($0) }
        )
    }

    // MARK: - Burn Timers

    private func startBurnElapsedTimer() {
        burnElapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let s = self.burnStartTime else { return }
                self.burnProgress.elapsedSeconds = Int(Date().timeIntervalSince(s))
            }
        }
    }

    private func stopBurnTimers() {
        burnElapsedTask?.cancel()
        burnElapsedTask = nil
        stopBurnLogPolling()
    }

    // MARK: - Private Pipelines

    private func createCDImage(device: String, output: URL, logPath: String) async {
        if outputFormat == .cueBin {
            // cdrdao read-cd produces TOC + BIN
            let tocPath = output.deletingPathExtension().appendingPathExtension("toc").path
            let (_, exitCode) = await discBurningService.readCD(
                device: device,
                outputFile: tocPath
            )
            if exitCode == 0 {
                appendLog("CUE/BIN image created successfully.")
                state = .finished
            } else {
                fail("CD read error (code \(exitCode))")
            }
        } else {
            // ISO from CD — read via cdrdao then convert, or use dd
            let (_, exitCode) = await discBurningService.readCD(
                device: device,
                outputFile: output.path
            )
            if exitCode == 0 {
                appendLog("ISO image created successfully.")
                state = .finished
            } else {
                fail("CD read error (code \(exitCode))")
            }
        }
    }

    private func createISOImage(bsdName: String?, output: URL, logPath: String) async {
        guard let bsd = bsdName else {
            fail("Unable to determine BSD device.")
            return
        }

        appendLog("Reading disc via dd (\(bsd))...")
        let (exitCode, errorMessage) = await discImageService.readToISO(
            bsdName: bsd,
            outputPath: output.path,
            logPath: logPath
        )

        if exitCode == 0 {
            appendLog("Image ISO créée avec succès.")
            state = .finished
        } else {
            fail(errorMessage.isEmpty ? "Read error (code \(exitCode))" : errorMessage)
        }
    }

    private func createEncryptedDVDImage(bsdName: String?, output: URL) async {
        guard let bsd = bsdName else {
            fail("Unable to determine BSD device.")
            return
        }

        guard decryptionService.isDvdCssAvailable else {
            fail("libdvdcss is not installed. Install it with: brew install libdvdcss")
            return
        }

        appendLog("Reading encrypted DVD via ffmpeg (\(bsd))...")
        let exitCode = await discImageService.readEncryptedDVD(
            bsdName: bsd,
            outputPath: output.path
        ) { [weak self] line in
            self?.appendLog(line)
        }

        if exitCode == 0 {
            appendLog("Image created successfully.")
            state = .finished
        } else {
            fail("Encrypted DVD read error (code \(exitCode))")
        }
    }

    // MARK: - Helpers

    private func fail(_ message: String) {
        state = .failed
        error = message
        appendLog("Error: \(message)")
    }

    // appendLog() provided by Loggable protocol extension

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
