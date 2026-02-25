import Foundation

/// Manages CUE/BIN, ISO, NRG, IMG disc image burning.
/// Replaces the existing BurnManager.
@MainActor
@Observable
class ImageDiscManager {
    // MARK: - State

    var imageURL: URL?
    var imageType: DiscImageType?
    var tocInfo: CueFile?
    var state: PipelineState = .idle
    var progress = BurnProgress()
    var log: [String] = []
    var error: String?

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let dvdService: DVDService

    // MARK: - Private

    private var logPollTask: Task<Void, Never>?
    private var elapsedTask: Task<Void, Never>?
    private var lastLogOffset: UInt64 = 0
    private var startTime: Date?
    private var cancelled = false
    private var stagingDir: String?

    // MARK: - Init

    init(compactDiscService: CompactDiscService, dvdService: DVDService) {
        self.compactDiscService = compactDiscService
        self.dvdService = dvdService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - Load Image

    func loadImage(url: URL) {
        imageURL = url
        imageType = DiscImageType.from(url: url)
        error = nil
        state = .idle
    }

    // MARK: - Burn

    func startBurn(device: String, settings: BurnSettings) async {
        guard let imageURL, let imageType else {
            fail("Aucune image sélectionnée.")
            return
        }

        cancelled = false
        error = nil
        progress = BurnProgress()
        progress.isSimulation = settings.simulate
        log = []

        state = settings.simulate ? .simulating : .burning
        startTimers()
        appendLog(settings.simulate ? "Démarrage de la simulation..." : "Démarrage de la gravure...")

        let logPath = "/tmp/burnman_image_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        startLogPolling(logPath: logPath)

        let exitCode: Int32
        let errorMessage: String

        switch imageType {
        case .cueBin:
            let dir = imageURL.deletingLastPathComponent().path
            stagingDir = dir

            var args = [String]()
            args.append(settings.simulate ? "simulate" : "write")
            args += ["--device", device]
            args += ["--speed", "\(settings.speed)"]
            if settings.rawMode { args.append("--driver generic-mmc-raw") }
            if settings.swapAudio { args.append("--swap") }
            if settings.overburn { args.append("--overburn") }
            if settings.eject { args.append("--eject") }
            args.append(imageURL.lastPathComponent)

            (exitCode, errorMessage) = await compactDiscService.write(
                tocFile: imageURL.lastPathComponent,
                device: device,
                simulate: settings.simulate,
                speed: settings.speed,
                overburn: settings.overburn,
                eject: settings.eject,
                workingDirectory: dir,
                logPath: logPath
            )

        case .iso:
            (exitCode, errorMessage) = await dvdService.burn(
                isoPath: imageURL.path,
                device: device,
                dvdCompat: true,
                logPath: logPath
            )

        case .nrg, .img:
            // NRG/IMG: attempt as ISO for now
            (exitCode, errorMessage) = await dvdService.burn(
                isoPath: imageURL.path,
                device: device,
                logPath: logPath
            )
        }

        stopLogPolling(logPath: logPath)
        stopTimers()

        if cancelled {
            return
        }

        if exitCode != 0 {
            fail(errorMessage.isEmpty ? "Erreur de gravure (code \(exitCode))" : errorMessage)
            return
        }

        state = .finished
        progress.phase = .completed
    }

    func startSimulation(device: String, settings: BurnSettings) async {
        var simSettings = settings
        simSettings.simulate = true
        await startBurn(device: device, settings: simSettings)
    }

    func cancel() {
        cancelled = true
        Task { @MainActor in
            _ = await compactDiscService.cancel()
        }
        state = .failed
        error = "Annulé par l'utilisateur"
        progress.phase = .failed("Annulé par l'utilisateur")
        stopTimers()
    }

    // MARK: - Log

    func appendLog(_ message: String) {
        log.append(message)
    }

    // MARK: - Log Polling

    private func startLogPolling(logPath: String) {
        lastLogOffset = 0
        logPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
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
            CdrdaoOutputParser.applyEvents(
                from: line,
                onPhase: { self.progress.phase = $0 },
                onProgress: { cur, tot in
                    self.progress.currentMB = cur
                    self.progress.totalMB = tot
                },
                onBuffer: { fifo, drive in
                    self.progress.bufferFillFIFO = fifo
                    self.progress.bufferFillDrive = drive
                },
                onTrack: { self.progress.currentTrack = $0 },
                onStartingWrite: { speed, sim in
                    self.progress.writeSpeed = speed
                    self.progress.isSimulation = sim
                },
                onWarning: { self.progress.warnings.append($0) }
            )
        }
    }

    // MARK: - Timers

    private func startTimers() {
        startTime = Date()
        elapsedTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let start = startTime {
                    progress.elapsedSeconds = Int(Date().timeIntervalSince(start))
                }
            }
        }
    }

    private func stopTimers() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
        progress.phase = .failed(message)
        stopTimers()
    }
}
