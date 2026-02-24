import Foundation

// MARK: - Burn Manager

@Observable
@MainActor
class BurnManager {
    var settings = BurnSettings()
    var progress = BurnProgress()
    var log: [String] = []
    var cueFile: CueFile?
    var missingFiles: [String] = []
    var isRunning = false

    let helperClient = HelperClient()

    private var toolRunner: ToolRunner?
    private var elapsedTask: Task<Void, Never>?
    private var logPollTask: Task<Void, Never>?
    private var startTime: Date?
    private var lastLogOffset: UInt64 = 0

    // MARK: - Load CUE file

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

        // Valider l'existence des fichiers BIN référencés
        missingFiles = tracks.compactMap { track in
            guard let fileURL = track.fileURL,
                  !FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            return track.fileName
        }
    }

    // MARK: - Build Arguments

    private func buildArguments(device: DiscDevice, cueFilePath: String? = nil) -> [String] {
        var args: [String] = ["write"]
        args += ["--speed", "\(settings.speed)"]
        args += ["--device", device.path]

        if settings.rawMode {
            args += ["--driver", "generic-mmc-raw"]
        }
        if settings.simulate { args.append("--simulate") }
        if settings.swapAudio { args.append("--swap") }
        if settings.eject { args.append("--eject") }
        if settings.overburn { args.append("--overburn") }

        if let path = cueFilePath ?? cueFile?.url.path { args.append(path) }

        return args
    }

    // MARK: - Start Burn

    func startBurn(device: DiscDevice) async {
        guard cueFile != nil else { return }

        isRunning = true
        progress = BurnProgress()
        progress.phase = .preparing
        log = []
        startTime = Date()
        startElapsedTimer()

        await runViaHelper(device: device)

        stopTimers()
        isRunning = false
    }

    // MARK: - Cancel

    func cancel() {
        toolRunner?.cancel()
        Task {
            _ = await helperClient.cancelCdrdao()
        }
        progress.phase = .failed("Annulé par l'utilisateur")
        stopTimers()
        isRunning = false
    }

    // MARK: - Privileged Execution via XPC Helper

    private func runViaHelper(device: DiscDevice) async {
        helperClient.checkInstallation()

        if !helperClient.isInstalled {
            appendLog("Installation du helper privilégié...")
            do {
                try helperClient.installHelper()
                appendLog("Helper installé.")
            } catch {
                progress.phase = .failed("Helper : \(error.localizedDescription)")
                return
            }
        }

        if let version = await helperClient.ping() {
            appendLog("Helper connecté (v\(version))")
        } else {
            // Retry: re-register daemon and try again
            appendLog("Reconnexion au helper…")
            do {
                try? helperClient.uninstallHelper()
                try helperClient.installHelper()
            } catch {
                progress.phase = .failed("Helper : \(error.localizedDescription)")
                return
            }
            if let version = await helperClient.ping() {
                appendLog("Helper connecté (v\(version))")
            } else {
                progress.phase = .failed("Impossible de contacter le helper (XPC 4097). Vérifiez Réglages Système > Général > Ouverture.")
                return
            }
        }

        // Stage files to a TCC-free temp directory
        let stagingDir = NSTemporaryDirectory() + "cdrburn_\(UUID().uuidString)"
        defer { try? FileManager.default.removeItem(atPath: stagingDir) }

        let stagedCuePath: String
        do {
            stagedCuePath = try stageFiles(to: stagingDir)
            appendLog("Fichiers préparés pour la gravure.")
        } catch {
            progress.phase = .failed("Préparation : \(error.localizedDescription)")
            return
        }

        let arguments = buildArguments(device: device, cueFilePath: stagedCuePath)
        appendLog("cdrdao \(arguments.joined(separator: " "))")

        // Fichier log pour progression temps réel
        let logPath = "/tmp/cdrburn_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        startLogPolling(logPath: logPath)
        progress.phase = .writingTrack(1)
        appendLog("Exécution via helper (root)...")

        let (exitCode, errorMessage) = await helperClient.runCdrdaoWithProgress(
            cdrdaoPath: CdrdaoConfig.resolvedPath,
            arguments: arguments,
            workingDirectory: stagingDir,
            logPath: logPath
        )

        stopLogPolling()
        // Lire les dernières lignes du log avant suppression
        pollLogFile(logPath: logPath)
        try? FileManager.default.removeItem(atPath: logPath)

        if exitCode == 0 {
            progress.phase = .completed
            appendLog("Gravure terminée.")
        } else {
            let description = describeExitCode(exitCode, helperMessage: errorMessage)
            progress.phase = .failed(description)
            appendLog("ERREUR : \(description)")
        }
    }

    // MARK: - Stage Files to /tmp/

    private func stageFiles(to stagingDir: String) throws -> String {
        guard let cue = cueFile else {
            throw NSError(domain: "BurnManager", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Aucun fichier CUE chargé"])
        }

        let fm = FileManager.default
        try fm.createDirectory(atPath: stagingDir, withIntermediateDirectories: true)

        // Re-activate security-scoped access for copying
        let accessing = cue.url.startAccessingSecurityScopedResource()
        defer { if accessing { cue.url.stopAccessingSecurityScopedResource() } }

        // Copy each unique referenced data file (flattened to basenames)
        var copied = Set<String>()
        for track in cue.tracks {
            guard let fileURL = track.fileURL else { continue }
            let baseName = fileURL.lastPathComponent
            guard !copied.contains(baseName) else { continue }
            copied.insert(baseName)
            try fm.copyItem(atPath: fileURL.path, toPath: "\(stagingDir)/\(baseName)")
        }

        // Rewrite CUE: replace FILE directives with basenames
        // (handles "../subdir/file.bin" → "file.bin")
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

    // MARK: - Exit Code Description

    private func describeExitCode(_ code: Int32, helperMessage: String) -> String {
        if !helperMessage.isEmpty { return helperMessage }
        switch code {
        case 0: return "Succès"
        case 1: return "Erreur cdrdao générale"
        case 2: return "Erreur d'utilisation cdrdao"
        case -1: return "Chemin cdrdao invalide"
        case -2: return "Arguments invalides"
        case -3: return "Répertoire de travail invalide"
        case -4: return "Chemin de log invalide"
        case -5: return "Impossible de lancer cdrdao"
        default:
            if code > 128 {
                let signal = code - 128
                if signal == 15 { return "cdrdao interrompu (annulation)" }
                return "cdrdao tué par signal \(signal)"
            }
            return "cdrdao code \(code)"
        }
    }

    // MARK: - Log Polling

    private func startLogPolling(logPath: String) {
        lastLogOffset = 0

        logPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.pollLogFile(logPath: logPath)
            }
        }
    }

    private func pollLogFile(logPath: String) {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastLogOffset)
        let data = handle.readDataToEndOfFile()
        lastLogOffset = handle.offsetInFile

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines { parseCdrdaoLine(line) }
    }

    private func stopLogPolling() {
        logPollTask?.cancel()
        logPollTask = nil
    }

    // MARK: - Parse cdrdao Output

    private func parseCdrdaoLine(_ line: String) {
        appendLog(line)

        CdrdaoOutputParser.applyEvents(
            from: line,
            onPhase: { progress.phase = $0 },
            onProgress: { progress.currentMB = $0; progress.totalMB = $1 },
            onBuffer: { progress.bufferFillFIFO = $0; progress.bufferFillDrive = $1 },
            onTrack: { progress.currentTrack = $0 },
            onStartingWrite: { progress.writeSpeed = $0; progress.isSimulation = $1 },
            onWarning: { progress.warnings.append($0) }
        )
    }

    // MARK: - Helpers

    private func appendLog(_ msg: String) {
        let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        log.append(t)
    }

    private func startElapsedTimer() {
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let s = self.startTime else { return }
                self.progress.elapsedSeconds = Int(Date().timeIntervalSince(s))
            }
        }
    }

    private func stopTimers() {
        elapsedTask?.cancel()
        elapsedTask = nil
        stopLogPolling()
    }
}
