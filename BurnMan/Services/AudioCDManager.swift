import Foundation
import Observation

// MARK: - Audio CD Manager

@MainActor
@Observable
class AudioCDManager {
    var tracks: [AudioTrack] = []
    var cdText = CDTextMetadata()
    var settings = AudioCDSettings()
    var progress = AudioCDProgress()
    var log: [String] = []
    var isRunning = false

    let helperClient = HelperClient()

    private var toolRunner: ToolRunner?
    private var elapsedTask: Task<Void, Never>?
    private var logPollTask: Task<Void, Never>?
    private var lastLogOffset: UInt64 = 0
    private var startTime: Date?
    private var cancelled = false
    private var tempDirectory: URL?
    private var currentDevice: DiscDevice?



    // MARK: - Computed

    var totalDurationSeconds: Double {
        tracks.reduce(0) { $0 + $1.durationSeconds }
    }

    var capacityFraction: Double {
        guard settings.cdType.maxSeconds > 0 else { return 0 }
        return totalDurationSeconds / Double(settings.cdType.maxSeconds)
    }

    var isOverCapacity: Bool { capacityFraction > 1.0 }

    var tracksNeedingConversion: [AudioTrack] {
        tracks.filter { $0.needsConversion }
    }

    var canBurn: Bool {
        !tracks.isEmpty && !isOverCapacity
    }

    // MARK: - Add Files

    func addFiles(urls: [URL]) async {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            if let track = await probeAudioFile(url: url) {
                tracks.append(track)
            }
        }
        renumberTracks()
        populateDiscCDText()
    }

    // MARK: - ffprobe

    private struct FfprobeResult {
        var duration: Double = 0
        var sampleRate: Double = 0
        var bitDepth: Int = 0
        var channels: Int = 0
        var tags: [String: String] = [:]  // keys UPPERCASED
    }

    private func runFfprobe(url: URL) async -> FfprobeResult? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let ffprobePath = FfmpegConfig.ffprobePath
        let filePath = url.path(percentEncoded: false)

        let proc = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.executableURL = URL(fileURLWithPath: ffprobePath)
        proc.arguments = ["-v", "error", "-print_format", "json",
                          "-show_format", "-show_streams", filePath]
        if let env = Bundle.main.privateFrameworksPath {
            var e = ProcessInfo.processInfo.environment
            e["DYLD_LIBRARY_PATH"] = env
            proc.environment = e
        }
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe
        
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        
        let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0 else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        var result = FfprobeResult()

        // Format
        if let format = json["format"] as? [String: Any] {
            result.duration = Double(format["duration"] as? String ?? "") ?? 0
            if let rawTags = format["tags"] as? [String: String] {
                result.tags = Dictionary(uniqueKeysWithValues: rawTags.map { ($0.key.uppercased(), $0.value) })
            }
        }

        // Audio stream
        let streams = json["streams"] as? [[String: Any]] ?? []
        if let audio = streams.first(where: { ($0["codec_type"] as? String) == "audio" }) {
            result.sampleRate = Double(audio["sample_rate"] as? String ?? "") ?? 0
            result.bitDepth = Int(audio["bits_per_raw_sample"] as? String ?? "")
                ?? (audio["bits_per_sample"] as? Int ?? 0)
            result.channels = audio["channels"] as? Int ?? 0
        }

        return result
    }

    // MARK: - Probe Audio File

    func probeAudioFile(url: URL) async -> AudioTrack? {
        guard let probe = await runFfprobe(url: url),
              probe.duration > 0 else { return nil }

        let fileName = url.deletingPathExtension().lastPathComponent

        let ext = url.pathExtension.uppercased()
        let sourceFormat: String
        switch ext {
        case "MP3": sourceFormat = "MP3"
        case "M4A", "AAC": sourceFormat = "AAC"
        case "FLAC": sourceFormat = "FLAC"
        case "WAV": sourceFormat = "WAV"
        case "AIFF", "AIF": sourceFormat = "AIFF"
        default: sourceFormat = ext
        }

        return AudioTrack(
            sourceURL: url,
            title: probe.tags["TITLE"] ?? fileName,
            artist: probe.tags["ARTIST"] ?? "",
            songwriter: probe.tags["COMPOSER"] ?? "",
            message: "",
            isrc: "",
            albumName: probe.tags["ALBUM"] ?? "",
            durationSeconds: probe.duration,
            sourceFormat: sourceFormat,
            sampleRate: probe.sampleRate,
            bitDepth: probe.bitDepth,
            channels: probe.channels,
            order: tracks.count + 1,
            convertedURL: nil
        )
    }

    // MARK: - Track Management

    func removeTrack(at offsets: IndexSet) {
        tracks.remove(atOffsets: offsets)
        renumberTracks()
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        renumberTracks()
    }

    func renumberTracks() {
        for i in tracks.indices {
            tracks[i].order = i + 1
        }
    }

    // MARK: - Auto-fill Metadata

    func fillMetadataFromFiles() async {
        guard !tracks.isEmpty else { return }

        for i in tracks.indices {
            guard let probe = await runFfprobe(url: tracks[i].sourceURL) else { continue }

            if let t = probe.tags["TITLE"], !t.isEmpty { tracks[i].title = t }
            if let a = probe.tags["ARTIST"], !a.isEmpty { tracks[i].artist = a }
            if let s = probe.tags["COMPOSER"], !s.isEmpty { tracks[i].songwriter = s }
            if let a = probe.tags["ALBUM"], !a.isEmpty { tracks[i].albumName = a }
        }

        populateDiscCDText(overwriteExisting: true)
    }

    // MARK: - Populate Disc CD-Text

    private func populateDiscCDText(overwriteExisting: Bool = false) {
        guard !tracks.isEmpty else { return }

        let albums = Set(tracks.compactMap { $0.albumName.isEmpty ? nil : $0.albumName })
        if albums.count == 1, let common = albums.first,
           (overwriteExisting || cdText.albumTitle.isEmpty) {
            cdText.albumTitle = common
        }

        let artists = Set(tracks.compactMap { $0.artist.isEmpty ? nil : $0.artist })
        if artists.count == 1, let common = artists.first,
           (overwriteExisting || cdText.albumArtist.isEmpty) {
            cdText.albumArtist = common
        }

        let songwriters = Set(tracks.compactMap { $0.songwriter.isEmpty ? nil : $0.songwriter })
        if songwriters.count == 1, let common = songwriters.first,
           (overwriteExisting || cdText.albumSongwriter.isEmpty) {
            cdText.albumSongwriter = common
        }
    }

    // MARK: - Pipeline

    func startPipeline(device: DiscDevice) async {
        guard canBurn else { return }

        isRunning = true
        cancelled = false
        currentDevice = device
        log = []
        progress = AudioCDProgress()
        startTime = Date()
        startElapsedTimer()

        appendLog("Démarrage du pipeline CD Audio...")

        // Validate
        progress.pipelinePhase = .validating
        guard validate(device: device) else {
            stopTimers()
            isRunning = false
            return
        }

        // Convert
        guard !cancelled else { return handleCancel() }
        let convertSuccess = await convertTracks()
        guard convertSuccess, !cancelled else {
            if !cancelled { progress.pipelinePhase = .failed("Erreur de conversion") }
            stopTimers()
            isRunning = false
            return
        }

        // Generate TOC
        guard !cancelled else { return handleCancel() }
        progress.pipelinePhase = .generatingTOC
        guard let tocURL = generateTOCFile() else {
            progress.pipelinePhase = .failed("Impossible de générer le fichier TOC")
            stopTimers()
            isRunning = false
            return
        }
        appendLog("Fichier TOC généré : \(tocURL.lastPathComponent)")

        // Burn
        guard !cancelled else { return handleCancel() }
        progress.pipelinePhase = .burning
        await executeBurn(device: device, tocURL: tocURL)

        // Cleanup
        if case .failed = progress.pipelinePhase {
            // Don't overwrite error
        } else {
            progress.pipelinePhase = .cleaningUp
        }
        cleanup()

        if case .failed = progress.pipelinePhase {
            // Keep error state
        } else {
            progress.pipelinePhase = .completed
            appendLog("Pipeline terminé avec succès.")
        }

        stopTimers()
        isRunning = false
    }

    func cancel() {
        cancelled = true
        toolRunner?.cancel()
        Task {
            _ = await helperClient.cancelCdrdao()
            // Wait briefly for cdrdao to terminate, then unlock the drive
            try? await Task.sleep(for: .seconds(1))
            await unlockDevice()
        }
        progress.pipelinePhase = .failed("Annulé par l'utilisateur")
        stopTimers()
        isRunning = false
    }

    // MARK: - Validate

    private func validate(device: DiscDevice) -> Bool {
        if tracks.isEmpty {
            progress.pipelinePhase = .failed("Aucune piste audio")
            return false
        }

        if isOverCapacity && !settings.overburn {
            progress.pipelinePhase = .failed("La durée totale dépasse la capacité du CD")
            return false
        }

        appendLog("Validation OK : \(tracks.count) piste(s), \(totalDurationSeconds.formatted(.number.precision(.fractionLength(0))))s")
        return true
    }

    // MARK: - Convert Tracks

    private func convertTracks() async -> Bool {
        guard !tracks.isEmpty else {
            appendLog("Aucune piste à convertir.")
            return true
        }

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            appendLog("ERREUR : impossible de créer le dossier temporaire")
            return false
        }
        tempDirectory = tempDir

        appendLog("Conversion de \(tracks.count) piste(s)...")

        for (idx, track) in tracks.enumerated() {
            guard !cancelled else { return false }

            let current = idx + 1
            progress.pipelinePhase = .converting(current: current, total: tracks.count)
            progress.conversionTrackIndex = current
            progress.conversionTotalTracks = tracks.count
            progress.conversionTrackProgress = 0

            let destName = String(format: "track%02d.wav", track.order)
            let destURL = tempDir.appendingPathComponent(destName)

            appendLog("Conversion : \(track.sourceURL.lastPathComponent) → \(destName)")

            let success = await convertToCDWav(source: track.sourceURL, destination: destURL, trackIndex: idx)
            guard success else {
                appendLog("ERREUR : échec de la conversion de \(track.sourceURL.lastPathComponent)")
                return false
            }

            // Verify output file
            let fm = FileManager.default
            guard fm.fileExists(atPath: destURL.path),
                  let attrs = try? fm.attributesOfItem(atPath: destURL.path),
                  let size = attrs[.size] as? UInt64, size > 0 else {
                appendLog("ERREUR : fichier converti manquant ou vide : \(destName)")
                return false
            }

            tracks[idx].convertedURL = destURL
            progress.conversionTrackProgress = 1.0
        }

        appendLog("Toutes les conversions terminées.")
        return true
    }

    private func convertToCDWav(source: URL, destination: URL, trackIndex: Int) async -> Bool {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let runner = ToolRunner()
        self.toolRunner = runner

        let totalDuration = tracks.first(where: { $0.sourceURL == source })?.durationSeconds ?? 0
        let session = FfmpegOutputParser.Session()

        let args = [
            "-i", source.path,
            "-ar", "44100",
            "-ac", "2",
            "-acodec", "pcm_s16le",
            "-f", "wav",
            "-y", destination.path,
            "-progress", "pipe:1",
            "-nostats"
        ]

        appendLog("ffmpeg \(args.joined(separator: " "))")

        let exitCode = await runner.run(
            executablePath: FfmpegConfig.resolvedPath,
            arguments: args
        ) { [weak self] line in
            guard let self else { return }
            if let event = session.feed(line: line) {
                switch event {
                case .progress(let timeSeconds, _):
                    if totalDuration > 0 {
                        self.progress.conversionTrackProgress = min(1.0, timeSeconds / totalDuration)
                    }
                case .completed:
                    self.progress.conversionTrackProgress = 1.0
                }
            }
            // Log uniquement les lignes qui ne sont pas du key=value ffmpeg (erreurs, warnings)
            if FfmpegOutputParser.parse(line: line) == nil {
                self.appendLog(line)
            }
        }

        if exitCode != 0 {
            appendLog("ERREUR : ffmpeg code \(exitCode)")
        }
        return exitCode == 0
    }

    // MARK: - Generate TOC File

    private func generateTOCFile() -> URL? {
        let tempDir = tempDirectory ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_\(UUID().uuidString)")

        if tempDirectory == nil {
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempDirectory = tempDir
        }

        let tocURL = tempDir.appendingPathComponent("audio.toc")

        var toc = "CD_DA\n\n"

        // Determine which CD-TEXT fields are used anywhere (disc or any track)
        let needsTitle = !cdText.albumTitle.isEmpty || tracks.contains { !$0.title.isEmpty }
        let needsPerformer = !cdText.albumArtist.isEmpty || tracks.contains { !$0.artist.isEmpty }
        let needsSongwriter = !cdText.albumSongwriter.isEmpty || tracks.contains { !$0.songwriter.isEmpty }
        let needsMessage = !cdText.albumMessage.isEmpty || tracks.contains { !$0.message.isEmpty }
        let hasAnyCDText = needsTitle || needsPerformer || needsSongwriter || needsMessage

        // Disc-level CD_TEXT
        if hasAnyCDText {
            toc += "CD_TEXT {\n"
            toc += "  LANGUAGE_MAP { 0 : EN }\n"
            toc += "  LANGUAGE 0 {\n"
            if needsTitle     { toc += "    TITLE \"\(escapeTOCString(cdText.albumTitle))\"\n" }
            if needsPerformer { toc += "    PERFORMER \"\(escapeTOCString(cdText.albumArtist))\"\n" }
            if needsSongwriter { toc += "    SONGWRITER \"\(escapeTOCString(cdText.albumSongwriter))\"\n" }
            if needsMessage   { toc += "    MESSAGE \"\(escapeTOCString(cdText.albumMessage))\"\n" }
            toc += "  }\n"
            toc += "}\n\n"
        }

        // Tracks
        for track in tracks {
            toc += "TRACK AUDIO\n"

            // Per-track ISRC (outside CD_TEXT block)
            if !track.isrc.isEmpty {
                toc += "  ISRC \"\(track.isrc)\"\n"
            }

            // Per-track CD-Text: emit ALL fields used anywhere for consistency
            if hasAnyCDText {
                toc += "  CD_TEXT {\n"
                toc += "    LANGUAGE 0 {\n"
                if needsTitle     { toc += "      TITLE \"\(escapeTOCString(track.title))\"\n" }
                if needsPerformer { toc += "      PERFORMER \"\(escapeTOCString(track.artist))\"\n" }
                if needsSongwriter { toc += "      SONGWRITER \"\(escapeTOCString(track.songwriter))\"\n" }
                if needsMessage   { toc += "      MESSAGE \"\(escapeTOCString(track.message))\"\n" }
                toc += "    }\n"
                toc += "  }\n"
            }

            // Audio file path (all tracks are converted to temp dir)
            guard let convertedURL = track.convertedURL else {
                appendLog("ERREUR : fichier converti manquant pour \(track.sourceURL.lastPathComponent)")
                return nil
            }
            let wavPath = convertedURL.lastPathComponent

            toc += "  AUDIOFILE \"\(wavPath)\" 0\n\n"
        }

        appendLog("TOC généré :\n\(toc)")

        do {
            try toc.write(to: tocURL, atomically: true, encoding: .utf8)
            return tocURL
        } catch {
            appendLog("ERREUR : impossible d'écrire le fichier TOC")
            return nil
        }
    }

    private func escapeTOCString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        // cdrdao treats "" as "not defined" — use a space to satisfy
        // the requirement that a field be present for all tracks/disc
        return escaped.isEmpty ? " " : escaped
    }

    // MARK: - Execute Burn

    private func executeBurn(device: DiscDevice, tocURL: URL) async {
        // Ensure helper is installed and connected
        helperClient.checkInstallation()

        if !helperClient.isInstalled {
            appendLog("Installation du helper privilégié...")
            do {
                try helperClient.installHelper()
                appendLog("Helper installé.")
            } catch {
                progress.pipelinePhase = .failed("Helper : \(error.localizedDescription)")
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
                progress.pipelinePhase = .failed("Helper : \(error.localizedDescription)")
                return
            }
            if let version = await helperClient.ping() {
                appendLog("Helper connecté (v\(version))")
            } else {
                progress.pipelinePhase = .failed("Impossible de contacter le helper (XPC 4097). Vérifiez Réglages Système > Général > Ouverture.")
                return
            }
        }

        let workingDirectory = (tempDirectory ?? tocURL.deletingLastPathComponent()).path

        var args: [String] = [settings.simulate ? "simulate" : "write"]
        args += ["--speed", "\(settings.speed)"]
        args += ["--device", device.path]
        if settings.eject { args.append("--eject") }
        if settings.overburn { args.append("--overburn") }
        args.append(tocURL.path)

        appendLog("cdrdao \(args.joined(separator: " "))")

        // Log file for real-time progress polling
        let logPath = "/tmp/cdrburn_audio_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        startLogPolling(logPath: logPath)
        appendLog("Exécution via helper (root)...")

        let (exitCode, errorMessage) = await helperClient.runCdrdaoWithProgress(
            cdrdaoPath: CdrdaoConfig.resolvedPath,
            arguments: args,
            workingDirectory: workingDirectory,
            logPath: logPath
        )

        stopLogPolling()
        // Read remaining log lines before cleanup
        pollLogFile(logPath: logPath)
        try? FileManager.default.removeItem(atPath: logPath)

        if exitCode == 0 {
            appendLog("Gravure terminée.")
        } else {
            // Unlock the drive after a failed burn/simulation
            await unlockDevice()

            if case .failed = progress.pipelinePhase {
                // Already set by parseCdrdaoLine
            } else {
                let description = describeExitCode(exitCode, helperMessage: errorMessage)
                progress.pipelinePhase = .failed(description)
                appendLog("ERREUR : \(description)")
            }
        }
    }

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

    private func parseCdrdaoLine(_ line: String) {
        appendLog(line)

        CdrdaoOutputParser.applyEvents(
            from: line,
            onPhase: { phase in
                progress.burnPhase = phase
                if case .failed(let msg) = phase,
                   case .burning = progress.pipelinePhase {
                    // Only set the first error; don't overwrite with subsequent ones
                    progress.pipelinePhase = .failed(msg)
                }
            },
            onProgress: { progress.currentMB = $0; progress.totalMB = $1 },
            onBuffer: { progress.bufferFillFIFO = $0; progress.bufferFillDrive = $1 },
            onTrack: { progress.currentTrack = $0 },
            onStartingWrite: { progress.writeSpeed = $0; progress.isSimulation = $1 },
            onWarning: { progress.warnings.append($0) }
        )
    }

    // MARK: - Cleanup

    private func cleanup() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            appendLog("Fichiers temporaires supprimés.")
        }
        tempDirectory = nil

        // Clear convertedURLs
        for i in tracks.indices {
            tracks[i].convertedURL = nil
        }
    }

    // MARK: - Unlock Device

    /// Runs `cdrdao unlock` to release a drive left in a locked state
    /// after an interrupted burn or simulation.
    private func unlockDevice() async {
        guard let device = currentDevice else { return }
        let args = ["unlock", "--device", device.path]
        appendLog("Déverrouillage du lecteur...")
        let (exitCode, _) = await helperClient.runCdrdaoWithProgress(
            cdrdaoPath: CdrdaoConfig.resolvedPath,
            arguments: args,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: "/tmp/cdrburn_unlock.log"
        )
        if exitCode == 0 {
            appendLog("Lecteur déverrouillé.")
        } else {
            appendLog("Impossible de déverrouiller le lecteur (code \(exitCode)).")
        }
        try? FileManager.default.removeItem(atPath: "/tmp/cdrburn_unlock.log")
    }

    // MARK: - Helpers

    private func appendLog(_ msg: String) {
        let t = msg.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        log.append(t)
    }

    private func handleCancel() {
        cleanup()
        stopTimers()
        isRunning = false
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
