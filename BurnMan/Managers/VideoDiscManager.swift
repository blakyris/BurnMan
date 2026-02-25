import AVFoundation
import Foundation

/// Manages DVD-Video and Blu-ray disc creation pipeline.
@MainActor
@Observable
class VideoDiscManager {
    // MARK: - State

    var files: [VideoFile] = []
    var discType: VideoDiscType = .dvd
    var state: PipelineState = .idle
    var error: String?

    // MARK: - Services

    let mediaProbeService: MediaProbeService
    let mediaConversionService: MediaConversionService
    let dvdService: DVDService
    let blurayService: BlurayService
    let mediaPlayerService: MediaPlayerService

    // MARK: - Private

    private var cancelled = false
    private var tempDirectory: URL?

    // MARK: - Init

    init(
        mediaProbeService: MediaProbeService,
        mediaConversionService: MediaConversionService,
        dvdService: DVDService,
        blurayService: BlurayService,
        mediaPlayerService: MediaPlayerService
    ) {
        self.mediaProbeService = mediaProbeService
        self.mediaConversionService = mediaConversionService
        self.dvdService = dvdService
        self.blurayService = blurayService
        self.mediaPlayerService = mediaPlayerService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - File Management

    func addFiles(urls: [URL]) async {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let info = try await mediaProbeService.probe(url: url)
                let file = VideoFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    duration: info.duration,
                    codec: info.videoStreams.first?.codec ?? "unknown",
                    resolution: info.videoStreams.first.map { "\($0.width)x\($0.height)" } ?? "",
                    fileSize: fileSize(at: url)
                )
                files.append(file)
            } catch {
                // Skip files that can't be probed
            }
        }
    }

    func removeFile(at offsets: IndexSet) {
        files.remove(atOffsets: offsets)
    }

    // MARK: - Preview

    func preview(url: URL) -> AVPlayer {
        mediaPlayerService.playVideo(url: url)
    }

    // MARK: - Burn Pipeline

    func startBurn(device: String) async {
        cancelled = false
        error = nil
        state = .preparing

        guard !files.isEmpty else {
            fail("Aucun fichier vidéo ajouté.")
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BurnMan_Video_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempDirectory = tempDir

        // Transcode
        for (index, file) in files.enumerated() {
            guard !cancelled else { return }
            state = .converting(current: index + 1, total: files.count)

            let outputURL: URL
            let exitCode: Int32

            switch discType {
            case .dvd:
                outputURL = tempDir.appendingPathComponent("\(file.name).mpg")
                exitCode = await mediaConversionService.encodeDVD(
                    input: file.url,
                    output: outputURL
                )
            case .bluray:
                outputURL = tempDir.appendingPathComponent("\(file.name).m2ts")
                exitCode = await mediaConversionService.encodeBluray(
                    input: file.url,
                    output: outputURL
                )
            }

            guard exitCode == 0 else {
                fail("Erreur de transcodage pour \(file.name)")
                return
            }
        }

        guard !cancelled else { return }

        // Burn
        state = .burning

        let logPath = "/tmp/burnman_video_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        // For now, burn the first transcoded file as ISO
        // Full DVD/BD structure building will be added later
        let (exitCode, errorMessage) = switch discType {
        case .dvd:
            await dvdService.burn(
                isoPath: tempDir.path,
                device: device,
                logPath: logPath
            )
        case .bluray:
            await blurayService.burn(
                isoPath: tempDir.path,
                device: device,
                logPath: logPath
            )
        }

        if exitCode != 0 {
            fail(errorMessage.isEmpty ? "Erreur de gravure (code \(exitCode))" : errorMessage)
            return
        }

        state = .finished
        cleanup()
    }

    func cancel() {
        cancelled = true
        Task { @MainActor in
            switch discType {
            case .dvd: _ = await dvdService.cancel()
            case .bluray: _ = await blurayService.cancel()
            }
        }
        state = .failed
        error = "Annulé par l'utilisateur"
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
        cleanup()
    }

    private func cleanup() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            tempDirectory = nil
        }
    }

    private func fileSize(at url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }
}

// MARK: - Video File Model

struct VideoFile: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var name: String
    var duration: Double
    var codec: String
    var resolution: String
    var fileSize: UInt64

    var durationFormatted: String {
        let min = Int(duration) / 60
        let sec = Int(duration) % 60
        return String(format: "%d:%02d", min, sec)
    }

    var fileSizeMB: Double {
        Double(fileSize) / 1_048_576.0
    }
}
