import Foundation

/// Manages the audio CD burning pipeline: files → probe → convert → TOC → burn.
@MainActor
@Observable
class AudioDiscManager {
    // MARK: - State

    var tracks: [AudioTrack] = []
    var cdText = CDTextMetadata()
    var settings = AudioCDSettings()
    var state: PipelineState = .idle
    var progress = AudioCDProgress()
    var log: [String] = []
    var error: String?

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let mediaProbeService: MediaProbeService
    let mediaConversionService: MediaConversionService

    // MARK: - Private

    private var elapsedTask: Task<Void, Never>?
    private var logPollTask: Task<Void, Never>?
    private var lastLogOffset: UInt64 = 0
    private var startTime: Date?
    private var cancelled = false
    private var tempDirectory: URL?
    private var currentDevice: String?

    // MARK: - Init

    init(
        compactDiscService: CompactDiscService,
        mediaProbeService: MediaProbeService,
        mediaConversionService: MediaConversionService
    ) {
        self.compactDiscService = compactDiscService
        self.mediaProbeService = mediaProbeService
        self.mediaConversionService = mediaConversionService
    }

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

    var isRunning: Bool { state.isActive }

    // MARK: - Add Files

    func addFiles(urls: [URL]) async {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let info = try await mediaProbeService.probe(url: url)
                guard let audio = info.audioStreams.first else { continue }

                let track = AudioTrack(
                    sourceURL: url,
                    title: info.tags["title"] ?? url.deletingPathExtension().lastPathComponent,
                    artist: info.tags["artist"] ?? "",
                    songwriter: info.tags["composer"] ?? "",
                    message: "",
                    isrc: "",
                    albumName: info.tags["album"] ?? "",
                    durationSeconds: info.duration,
                    sourceFormat: audio.codec.uppercased(),
                    sampleRate: audio.sampleRate,
                    bitDepth: audio.bitDepth,
                    channels: audio.channels,
                    order: tracks.count + 1
                )
                tracks.append(track)
            } catch {
                appendLog("Erreur probe \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Track Management

    func removeTrack(at offsets: IndexSet) {
        tracks.remove(atOffsets: offsets)
        reorderTracks()
    }

    func moveTrack(from source: IndexSet, to destination: Int) {
        tracks.move(fromOffsets: source, toOffset: destination)
        reorderTracks()
    }

    private func reorderTracks() {
        for i in tracks.indices {
            tracks[i].order = i + 1
        }
    }

    // MARK: - Metadata

    func fillMetadataFromTags() async {
        for i in tracks.indices {
            do {
                let info = try await mediaProbeService.probe(url: tracks[i].sourceURL)
                if !info.tags.isEmpty {
                    if tracks[i].title.isEmpty { tracks[i].title = info.tags["title"] ?? "" }
                    if tracks[i].artist.isEmpty { tracks[i].artist = info.tags["artist"] ?? "" }
                    if tracks[i].albumName.isEmpty { tracks[i].albumName = info.tags["album"] ?? "" }
                }
            } catch {
                // Skip tracks that can't be probed
            }
        }
    }

    // MARK: - Burn Pipeline

    func startBurn(device: String) async {
        await runPipeline(device: device, simulate: false)
    }

    func startSimulation(device: String) async {
        await runPipeline(device: device, simulate: true)
    }

    func cancel() {
        cancelled = true
        Task { @MainActor in
            _ = await compactDiscService.cancel()
            try? await Task.sleep(for: .seconds(1))
            await unlockDevice()
        }
        state = .failed
        error = "Annulé par l'utilisateur"
        stopTimers()
    }

    // MARK: - Private Pipeline

    private func runPipeline(device: String, simulate: Bool) async {
        cancelled = false
        error = nil
        currentDevice = device
        progress = AudioCDProgress()
        progress.isSimulation = simulate
        log = []

        // Validate
        state = .preparing
        progress.pipelinePhase = .validating

        guard !tracks.isEmpty else {
            fail("Aucun fichier audio ajouté.")
            return
        }

        if !settings.overburn && isOverCapacity {
            fail("La durée totale dépasse la capacité du disque.")
            return
        }

        // Convert tracks
        let toConvert = tracksNeedingConversion
        if !toConvert.isEmpty {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("BurnMan_\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            tempDirectory = tempDir

            for (index, track) in toConvert.enumerated() {
                guard !cancelled else { return }

                let current = index + 1
                let total = toConvert.count
                state = .converting(current: current, total: total)
                progress.pipelinePhase = .converting(current: current, total: total)
                progress.conversionTrackIndex = current
                progress.conversionTotalTracks = total

                let outputURL = tempDir.appendingPathComponent("track_\(track.order).wav")
                let exitCode = await mediaConversionService.convertToCDWav(
                    input: track.sourceURL,
                    output: outputURL
                ) { [weak self] pct in
                    self?.progress.conversionTrackProgress = pct
                }

                guard exitCode == 0 else {
                    fail("Erreur de conversion pour \(track.fileName)")
                    return
                }

                if let trackIndex = tracks.firstIndex(where: { $0.id == track.id }) {
                    tracks[trackIndex].convertedURL = outputURL
                }
            }
        }

        guard !cancelled else { return }

        // Generate TOC
        state = .preparing
        progress.pipelinePhase = .generatingTOC
        appendLog("Génération du fichier TOC...")

        // Note: CueGenerator creates the TOC file — implementation depends on existing CueGenerator
        // For now, the TOC generation is handled at this level

        guard !cancelled else { return }

        // Burn
        state = simulate ? .simulating : .burning
        progress.pipelinePhase = .burning
        startTimers()
        appendLog(simulate ? "Démarrage de la simulation..." : "Démarrage de la gravure...")

        // The actual burn execution will be wired up when migrating from AudioCDManager
        // For now, placeholder:
        appendLog("Pipeline complet.")

        guard !cancelled else { return }

        // Cleanup
        state = .finished
        progress.pipelinePhase = .completed
        stopTimers()
        await unlockDevice()
        cleanup()
    }

    private func unlockDevice() async {
        guard let device = currentDevice else { return }
        appendLog("Déverrouillage du lecteur...")
        let (exitCode, _) = await compactDiscService.unlock(device: device)
        if exitCode == 0 {
            appendLog("Lecteur déverrouillé.")
        }
    }

    private func fail(_ message: String) {
        state = .failed
        error = message
        progress.pipelinePhase = .failed(message)
        stopTimers()
        cleanup()
    }

    private func cleanup() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
    }

    // MARK: - Log

    func appendLog(_ message: String) {
        log.append(message)
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
        logPollTask?.cancel()
        logPollTask = nil
    }
}
