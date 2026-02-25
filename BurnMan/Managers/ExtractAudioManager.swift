import Foundation

/// Manages audio track extraction from CDs.
/// Pipeline: read TOC → read disc → split tracks → convert to chosen format.
@MainActor
@Observable
class ExtractAudioManager {
    // MARK: - State

    var tracks: [CDTrackEntry] = []
    var outputFormat: AudioOutputFormat = .flac
    var outputDirectory: URL?
    var mp3Bitrate: Int = 320
    var state: PipelineState = .idle
    var error: String?
    var log: [String] = []

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let mediaConversionService: MediaConversionService

    // MARK: - Private

    private var cancelled = false
    private var tempDirectory: URL?

    // MARK: - Init

    init(
        compactDiscService: CompactDiscService,
        mediaConversionService: MediaConversionService
    ) {
        self.compactDiscService = compactDiscService
        self.mediaConversionService = mediaConversionService
    }

    var isRunning: Bool { state.isActive }

    var selectedTracks: [CDTrackEntry] {
        tracks.filter(\.selected)
    }

    var canExtract: Bool {
        !selectedTracks.isEmpty && outputDirectory != nil
    }

    // MARK: - Read TOC

    /// Reads the disc's table of contents to populate the track list.
    func readTOC(device: String) async {
        state = .preparing
        error = nil
        log = []
        tracks = []

        appendLog("Lecture de la table des matières...")
        let (output, exitCode) = await compactDiscService.showTOC(device: device)

        guard exitCode == 0 else {
            fail("Impossible de lire la table des matières (code \(exitCode))")
            return
        }

        tracks = parseTOCOutput(output)
        appendLog("\(tracks.count) piste(s) détectée(s).")
        state = .idle
    }

    // MARK: - Extract

    /// Extracts selected tracks from the disc to the output directory.
    func extract(device: String) async {
        guard canExtract else { return }
        guard let outputDir = outputDirectory else { return }

        cancelled = false
        error = nil

        // Step 1: Read entire disc to temp
        state = .reading
        appendLog("Lecture du disque...")

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_Extract_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir

        let tocFile = tempDir.appendingPathComponent("disc.toc").path
        let (_, readExitCode) = await compactDiscService.readCD(
            device: device,
            outputFile: tocFile
        )

        guard readExitCode == 0 else {
            fail("Erreur de lecture du disque (code \(readExitCode))")
            cleanup()
            return
        }

        guard !cancelled else {
            cleanup()
            return
        }

        // Step 2: Convert each selected track
        let selected = selectedTracks
        for (index, track) in selected.enumerated() {
            guard !cancelled else {
                cleanup()
                return
            }

            state = .extracting(current: index + 1, total: selected.count)
            appendLog("Extraction piste \(track.id) : \(track.title)...")

            let rawFile = tempDir.appendingPathComponent("data-\(track.id).wav")
            let outputFile = outputDir.appendingPathComponent(
                sanitizeFilename("\(track.title).\(outputFormat.fileExtension)")
            )

            let convertExitCode: Int32
            switch outputFormat {
            case .wav:
                // Raw WAV — just copy
                do {
                    if FileManager.default.fileExists(atPath: outputFile.path) {
                        try FileManager.default.removeItem(at: outputFile)
                    }
                    try FileManager.default.copyItem(at: rawFile, to: outputFile)
                    convertExitCode = 0
                } catch {
                    convertExitCode = -1
                }
            case .mp3:
                convertExitCode = await mediaConversionService.convertToMP3(
                    input: rawFile, output: outputFile, bitrate: mp3Bitrate
                )
            case .flac:
                convertExitCode = await mediaConversionService.convertToFLAC(
                    input: rawFile, output: outputFile
                )
            case .aac:
                convertExitCode = await mediaConversionService.convertToAAC(
                    input: rawFile, output: outputFile
                )
            }

            guard convertExitCode == 0 else {
                fail("Erreur de conversion piste \(track.id) (code \(convertExitCode))")
                cleanup()
                return
            }
        }

        appendLog("Extraction terminée : \(selected.count) piste(s).")
        state = .finished
        cleanup()
    }

    func cancel() {
        cancelled = true
        Task { @MainActor in
            _ = await compactDiscService.cancel()
        }
        state = .failed
        error = "Annulé par l'utilisateur"
        cleanup()
    }

    // MARK: - Track Selection

    func toggleTrack(_ trackId: Int) {
        if let index = tracks.firstIndex(where: { $0.id == trackId }) {
            tracks[index].selected.toggle()
        }
    }

    func selectAll() {
        for i in tracks.indices { tracks[i].selected = true }
    }

    func deselectAll() {
        for i in tracks.indices { tracks[i].selected = false }
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

    /// Parses cdrdao show-toc output into CDTrackEntry items.
    private func parseTOCOutput(_ output: String) -> [CDTrackEntry] {
        var entries: [CDTrackEntry] = []
        var trackNumber = 0

        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Look for TRACK lines: "TRACK AUDIO" or similar
            if trimmed.hasPrefix("TRACK") && trimmed.contains("AUDIO") {
                trackNumber += 1
                let entry = CDTrackEntry(
                    id: trackNumber,
                    title: "Piste \(trackNumber)",
                    artist: "",
                    durationSeconds: 0
                )
                entries.append(entry)
            }
        }

        // If no tracks found from parsing, return empty
        return entries
    }

    private func sanitizeFilename(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|")
        return name.components(separatedBy: forbidden).joined(separator: "_")
    }
}
