import AVFoundation
import Foundation

/// Manages audio and video preview playback.
/// Only @Observable service — owns playback state.
@MainActor
@Observable
class MediaPlayerService {
    /// ID of the track currently playing (nil if stopped).
    private(set) var playingTrackID: UUID?
    private(set) var isPlaying = false

    private var process: Process?
    private var avPlayer: AVPlayer?

    // MARK: - Audio Playback (ffplay)

    /// Plays an audio file via ffplay.
    func playAudio(trackID: UUID, url: URL) {
        stop()

        let accessing = url.startAccessingSecurityScopedResource()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ToolPaths.ffplay)
        proc.arguments = [
            "-nodisp",       // no video window
            "-autoexit",     // quit when done
            "-loglevel", "quiet",
            url.path,
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { @Sendable [weak self] terminatedProc in
            ProcessTracker.shared.unregister(terminatedProc)
            if accessing { url.stopAccessingSecurityScopedResource() }
            Task { @MainActor [weak self] in
                guard let self, self.playingTrackID == trackID else { return }
                self.playingTrackID = nil
                self.isPlaying = false
                self.process = nil
            }
        }

        do {
            try proc.run()
            ProcessTracker.shared.register(proc)
            self.process = proc
            self.playingTrackID = trackID
            self.isPlaying = true
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            self.process = nil
            self.playingTrackID = nil
            self.isPlaying = false
        }
    }

    // MARK: - Video Playback (AVPlayer)

    /// Returns an AVPlayer for a compatible video file.
    /// The caller (Manager) is responsible for checking format compatibility
    /// and converting via MediaConversionService if needed.
    func playVideo(url: URL) -> AVPlayer {
        stop()
        let player = AVPlayer(url: url)
        self.avPlayer = player
        self.isPlaying = true
        player.play()
        return player
    }

    // MARK: - Controls

    /// Toggle play/stop for a given track.
    func toggle(trackID: UUID, url: URL) {
        if playingTrackID == trackID {
            stop()
        } else {
            playAudio(trackID: trackID, url: url)
        }
    }

    func pause() {
        if let proc = process, proc.isRunning {
            proc.suspend()
        }
        avPlayer?.pause()
        isPlaying = false
    }

    func resume() {
        if let proc = process, proc.isRunning {
            proc.resume()
        }
        avPlayer?.play()
        isPlaying = true
    }

    func stop() {
        // Stop ffplay process
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil

        // Stop AVPlayer
        avPlayer?.pause()
        avPlayer = nil

        playingTrackID = nil
        isPlaying = false
    }
}
