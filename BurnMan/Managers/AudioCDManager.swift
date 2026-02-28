import Foundation
import Observation
import VLCKit

// MARK: - VLC Media Parse Delegate

/// Bridges VLCKit's delegate-based parsing to async/await.
/// Not @MainActor — mediaDidFinishParsing is called from VLC's internal thread.
private final class MediaParseDelegate: NSObject, VLCMediaDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func parse(_ media: VLCMedia) async {
        media.delegate = self
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
            media.parse(options: VLCMediaParsingOptions(rawValue: 0x00), timeout: 3000)
        }
    }

    func mediaDidFinishParsing(_ aMedia: VLCMedia) {
        continuation?.resume()
        continuation = nil
    }
}

// MARK: - Audio CD Manager

@MainActor
@Observable
class AudioCDManager: Loggable {
    var tracks: [AudioTrack] = []
    var cdText = CDTextMetadata()
    var settings = AudioCDSettings()
    var progress = AudioCDProgress()
    var log: [String] = []
    var isRunning = false

    let mediaProbeService: MediaProbeService
    let mediaConversionService: MediaConversionService
    let discBurningService: DiscBurningService

    private var elapsedTask: Task<Void, Never>?
    private let logPoller = LogFilePoller()
    private var startTime: Date?
    private var cancelled = false
    private var tempDirectory: URL?
    private var currentDevice: DiscDevice?

    init(mediaProbeService: MediaProbeService, mediaConversionService: MediaConversionService, discBurningService: DiscBurningService) {
        self.mediaProbeService = mediaProbeService
        self.mediaConversionService = mediaConversionService
        self.discBurningService = discBurningService
    }

    // MARK: - Computed

    var hasContent: Bool { !tracks.isEmpty }

    func reset() {
        if isRunning { cancel() }
        tracks = []
        cdText = CDTextMetadata()
        settings = AudioCDSettings()
        progress = AudioCDProgress()
        log = []
        isRunning = false
    }

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
        // Phase 1: Parse all files concurrently via VLCKit (fast, in-process)
        let newTracks = await withTaskGroup(
            of: (Int, AudioTrack?).self,
            returning: [AudioTrack].self
        ) { group in
            for (index, url) in urls.enumerated() {
                group.addTask {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    let track = await self.probeAudioFileWithVLC(url: url)
                    return (index, track)
                }
            }

            var results = [(Int, AudioTrack)]()
            for await (index, track) in group {
                if let track { results.append((index, track)) }
            }
            return results.sorted(by: { $0.0 < $1.0 }).map(\.1)
        }

        // Phase 2: Resolve WAV bit depth via lightweight ffprobe (VLCKit doesn't expose it)
        var resolved = newTracks
        for i in resolved.indices where resolved[i].sourceFormat == "WAV" {
            let url = resolved[i].sourceURL
            let accessing = url.startAccessingSecurityScopedResource()
            resolved[i].bitDepth = await mediaProbeService.probeBitDepth(url: url)
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        tracks.append(contentsOf: resolved)
        renumberTracks()
    }

    // MARK: - VLCKit Probe

    private func probeAudioFileWithVLC(url: URL) async -> AudioTrack? {
        let media = VLCMedia(url: url)
        let delegate = MediaParseDelegate()
        await delegate.parse(media)

        let durationMs = Int(media.length.intValue)
        guard durationMs > 0 else { return nil }
        let durationSeconds = Double(durationMs) / 1000.0

        let fileName = url.deletingPathExtension().lastPathComponent
        let meta = media.metaData
        let title = meta.title ?? ""
        let artist = meta.artist ?? ""
        let album = meta.album ?? ""

        var sampleRate: Double = 0
        var channels: Int = 0
        if let tracks = media.tracksInformation as? [[String: Any]] {
            for info in tracks {
                if let type = info[VLCMediaTracksInformationType] as? String,
                   type == VLCMediaTracksInformationTypeAudio {
                    sampleRate = Double(info[VLCMediaTracksInformationAudioRate] as? Int ?? 0)
                    channels = info[VLCMediaTracksInformationAudioChannelsNumber] as? Int ?? 0
                    break
                }
            }
        }

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
            title: title.isEmpty ? fileName : title,
            artist: artist,
            songwriter: "",
            message: "",
            isrc: "",
            albumName: album,
            durationSeconds: durationSeconds,
            sourceFormat: sourceFormat,
            sampleRate: sampleRate,
            bitDepth: 0,
            channels: channels,
            order: 0,
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

    func sortTracks(using comparators: [KeyPathComparator<AudioTrack>]) {
        tracks.sort(using: comparators)
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

        let probes = await withTaskGroup(
            of: (Int, AudioFileProbeResult?).self,
            returning: [(Int, AudioFileProbeResult)].self
        ) { group in
            for i in tracks.indices {
                let url = tracks[i].sourceURL
                group.addTask { (i, await self.mediaProbeService.probeAudioFile(url: url)) }
            }
            var results = [(Int, AudioFileProbeResult)]()
            for await (i, probe) in group {
                if let probe { results.append((i, probe)) }
            }
            return results
        }

        for (i, probe) in probes {
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

        appendLog("Starting Audio CD pipeline...")

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
            if !cancelled { progress.pipelinePhase = .failed("Conversion error") }
            stopTimers()
            isRunning = false
            return
        }

        // Generate TOC
        guard !cancelled else { return handleCancel() }
        progress.pipelinePhase = .generatingTOC
        guard let tocURL = generateTOCFile() else {
            progress.pipelinePhase = .failed("Unable to generate TOC file")
            stopTimers()
            isRunning = false
            return
        }
        appendLog("TOC file generated: \(tocURL.lastPathComponent)")

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
            appendLog("Pipeline completed successfully.")
        }

        stopTimers()
        isRunning = false
    }

    func cancel() {
        cancelled = true
        mediaConversionService.cancel()
        discBurningService.cancelCdrdao()
        Task {
            // Wait briefly for cdrdao to terminate, then unlock the drive
            try? await Task.sleep(for: .seconds(1))
            await unlockDevice()
        }
        progress.pipelinePhase = .failed("Cancelled by user")
        stopTimers()
        isRunning = false
    }

    // MARK: - Validate

    private func validate(device: DiscDevice) -> Bool {
        if tracks.isEmpty {
            progress.pipelinePhase = .failed("No audio tracks")
            return false
        }

        if isOverCapacity && !settings.overburn {
            progress.pipelinePhase = .failed("Total duration exceeds CD capacity")
            return false
        }

        appendLog("Validation OK: \(tracks.count) track(s), \(totalDurationSeconds.formatted(.number.precision(.fractionLength(0))))s")
        return true
    }

    // MARK: - Convert Tracks

    private func convertTracks() async -> Bool {
        guard !tracks.isEmpty else {
            appendLog("No tracks to convert.")
            return true
        }

        // Create temp directory
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            appendLog("ERROR: unable to create temporary directory")
            return false
        }
        tempDirectory = tempDir

        appendLog("Converting \(tracks.count) track(s)...")

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

            let accessing = track.sourceURL.startAccessingSecurityScopedResource()
            let exitCode = await mediaConversionService.convertToCDWav(
                input: track.sourceURL,
                output: destURL
            ) { [weak self] pct in
                self?.progress.conversionTrackProgress = pct
            }
            if accessing { track.sourceURL.stopAccessingSecurityScopedResource() }

            let success = exitCode == 0
            if !success { appendLog("ERREUR : ffmpeg code \(exitCode)") }
            guard success else {
                appendLog("ERROR: conversion failed for \(track.sourceURL.lastPathComponent)")
                return false
            }

            // Verify output file
            let fm = FileManager.default
            guard fm.fileExists(atPath: destURL.path),
                  let attrs = try? fm.attributesOfItem(atPath: destURL.path),
                  let size = attrs[.size] as? UInt64, size > 0 else {
                appendLog("ERROR: converted file missing or empty: \(destName)")
                return false
            }

            tracks[idx].convertedURL = destURL
            progress.conversionTrackProgress = 1.0
        }

        appendLog("All conversions completed.")
        return true
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

        // Map tracks to DiscDescriptor types
        let descriptors: [DiscDescriptor.AudioTrackDescriptor] = tracks.compactMap { track in
            guard let convertedURL = track.convertedURL else {
                appendLog("ERROR: converted file missing for \(track.sourceURL.lastPathComponent)")
                return nil
            }
            return DiscDescriptor.AudioTrackDescriptor(
                wavFileName: convertedURL.lastPathComponent,
                title: track.title,
                artist: track.artist,
                songwriter: track.songwriter,
                message: track.message,
                isrc: track.isrc
            )
        }

        guard descriptors.count == tracks.count else { return nil }

        let discCDText = DiscDescriptor.DiscCDText(
            albumTitle: cdText.albumTitle,
            albumArtist: cdText.albumArtist,
            albumSongwriter: cdText.albumSongwriter,
            albumMessage: cdText.albumMessage
        )

        let toc = DiscDescriptor.generateToc(tracks: descriptors, cdText: discCDText)
        appendLog("TOC generated:\n\(toc)")

        do {
            try toc.write(to: tocURL, atomically: true, encoding: .utf8)
            return tocURL
        } catch {
            appendLog("ERROR: unable to write TOC file")
            return nil
        }
    }

    // MARK: - Execute Burn

    private func executeBurn(device: DiscDevice, tocURL: URL) async {
        let workingDirectory = (tempDirectory ?? tocURL.deletingLastPathComponent()).path

        let options = CdrdaoOptions(
            speed: settings.speed,
            simulate: settings.simulate,
            eject: settings.eject,
            overburn: settings.overburn
        )

        appendLog("cdrdao \(settings.simulate ? "simulate" : "write") → \(tocURL.lastPathComponent)")

        // Log file for real-time progress polling
        let logPath = HelperLogPath.audioBurn
        FileManager.default.createFile(atPath: logPath, contents: nil)

        startLogPolling(logPath: logPath)
        appendLog("Running via helper (root)...")

        let (exitCode, errorMessage) = await discBurningService.writeCdrdao(
            tocFile: tocURL.path,
            device: device.path,
            options: options,
            workingDirectory: workingDirectory,
            logPath: logPath
        )

        stopLogPolling(flush: true)
        try? FileManager.default.removeItem(atPath: logPath)

        if exitCode == 0 {
            appendLog("Burn completed.")
        } else {
            // Unlock the drive after a failed burn/simulation
            await unlockDevice()

            if case .failed = progress.pipelinePhase {
                // Already set by parseCdrdaoLine
            } else {
                let description = CdrdaoOutputParser.describeExitCode(exitCode, helperMessage: errorMessage)
                progress.pipelinePhase = .failed(description)
                appendLog("ERREUR : \(description)")
            }
        }
    }

    // MARK: - Log Polling

    private func startLogPolling(logPath: String) {
        logPoller.start(logPath: logPath) { [weak self] lines in
            for line in lines { self?.parseCdrdaoLine(line) }
        }
    }

    private func stopLogPolling(flush: Bool = false) {
        logPoller.stop(logPath: HelperLogPath.audioBurn) { [weak self] lines in
            guard flush else { return }
            for line in lines { self?.parseCdrdaoLine(line) }
        }
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
            appendLog("Temporary files deleted.")
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
        appendLog("Unlocking drive...")
        let (exitCode, _) = await discBurningService.unlock(device: device.path)
        if exitCode == 0 {
            appendLog("Drive unlocked.")
        } else {
            appendLog("Unable to unlock drive (code \(exitCode)).")
        }
        try? FileManager.default.removeItem(atPath: HelperLogPath.unlock)
    }

    // MARK: - Helpers

    // appendLog() provided by Loggable protocol extension

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
