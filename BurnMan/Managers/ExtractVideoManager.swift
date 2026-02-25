import Foundation

/// Manages video title extraction from DVDs and Blu-rays.
/// Pipeline: probe titles → select title → extract with chosen format.
@MainActor
@Observable
class ExtractVideoManager {
    // MARK: - State

    var titles: [DVDTitle] = []
    var selectedTitleId: Int?
    var outputFormat: VideoOutputFormat = .mkv
    var outputURL: URL?
    var state: PipelineState = .idle
    var error: String?
    var log: [String] = []
    var progress: Double = 0

    // MARK: - Services

    let mediaConversionService: MediaConversionService
    let mediaProbeService: MediaProbeService
    let decryptionService: DecryptionService

    // MARK: - Private

    private var cancelled = false

    // MARK: - Init

    init(
        mediaConversionService: MediaConversionService,
        mediaProbeService: MediaProbeService,
        decryptionService: DecryptionService
    ) {
        self.mediaConversionService = mediaConversionService
        self.mediaProbeService = mediaProbeService
        self.decryptionService = decryptionService
    }

    var isRunning: Bool { state.isActive }

    var selectedTitle: DVDTitle? {
        titles.first { $0.id == selectedTitleId }
    }

    var canExtract: Bool {
        selectedTitleId != nil && outputURL != nil
    }

    // MARK: - Probe Titles

    /// Probes the disc device for available titles using ffprobe.
    func probeTitles(devicePath: String) async {
        state = .preparing
        error = nil
        log = []
        titles = []
        selectedTitleId = nil

        appendLog("Analyse du disque...")

        // Probe titles 1-99 via MediaProbeService
        var found: [DVDTitle] = []

        for titleNum in 1...99 {
            guard !cancelled else { break }

            guard let data = await mediaProbeService.probeDVDTitle(
                devicePath: devicePath,
                titleNumber: titleNum
            ) else {
                // No more titles
                break
            }

            if let info = parseTitleInfo(data: data, titleNumber: titleNum) {
                found.append(info)
            }
        }

        titles = found

        if titles.isEmpty {
            fail("Aucun titre trouvé sur le disque.")
            return
        }

        // Auto-select the longest title (likely the main feature)
        selectedTitleId = titles.max(by: { $0.duration < $1.duration })?.id

        appendLog("\(titles.count) titre(s) détecté(s).")
        state = .idle
    }

    // MARK: - Extract

    /// Extracts the selected title from the disc.
    func extract(devicePath: String) async {
        guard canExtract else { return }
        guard let output = outputURL else { return }
        guard let titleId = selectedTitleId else { return }

        cancelled = false
        error = nil
        progress = 0
        state = .extracting(current: 1, total: 1)
        appendLog("Extraction du titre \(titleId)...")

        let exitCode = await mediaConversionService.extractDVDTitle(
            devicePath: devicePath,
            titleNumber: titleId,
            output: output,
            codec: outputFormat.codec
        ) { [weak self] value in
            self?.progress = value
        }

        guard exitCode == 0 else {
            fail("Erreur d'extraction (code \(exitCode))")
            return
        }

        appendLog("Extraction terminée.")
        state = .finished
    }

    func cancel() {
        cancelled = true
        mediaConversionService.cancel()
        state = .failed
        error = "Annulé par l'utilisateur"
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

    private func parseTitleInfo(data: Data, titleNumber: Int) -> DVDTitle? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Get duration from format
        var duration: Double = 0
        if let format = json["format"] as? [String: Any],
           let durationStr = format["duration"] as? String,
           let d = Double(durationStr)
        {
            duration = d
        }

        // Skip very short titles (< 10 seconds — likely menus)
        guard duration > 10 else { return nil }

        // Count streams
        var audioLabels: [String] = []
        var subtitleLabels: [String] = []
        var chapterCount = 0

        if let streams = json["streams"] as? [[String: Any]] {
            for stream in streams {
                let codecType = stream["codec_type"] as? String ?? ""
                let language = (stream["tags"] as? [String: Any])?["language"] as? String ?? "und"
                switch codecType {
                case "audio":
                    let codecName = stream["codec_name"] as? String ?? "?"
                    audioLabels.append("\(language) (\(codecName))")
                case "subtitle":
                    subtitleLabels.append(language)
                default:
                    break
                }
            }
        }

        if let chapters = json["chapters"] as? [[String: Any]] {
            chapterCount = chapters.count
        }

        return DVDTitle(
            id: titleNumber,
            duration: duration,
            chapters: chapterCount,
            audioStreams: audioLabels,
            subtitleStreams: subtitleLabels
        )
    }
}
