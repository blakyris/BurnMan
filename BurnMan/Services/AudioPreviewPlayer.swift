import Foundation

/// Plays audio file previews using ffplay.
/// Only one track can play at a time — starting a new one stops the previous.
@MainActor
@Observable
class AudioPreviewPlayer {
    /// ID of the track currently playing (nil if stopped)
    private(set) var playingTrackID: UUID?

    private var process: Process?

    /// Toggle playback for a given track.
    /// If the track is already playing, stop it. Otherwise start it (stopping any other).
    func toggle(trackID: UUID, url: URL) {
        if playingTrackID == trackID {
            stop()
        } else {
            play(trackID: trackID, url: url)
        }
    }

    func stop() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        playingTrackID = nil
    }

    // MARK: - Private

    private func play(trackID: UUID, url: URL) {
        stop()

        let accessing = url.startAccessingSecurityScopedResource()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: FfmpegConfig.ffplayPath)
        proc.arguments = [
            "-nodisp",       // no video window
            "-autoexit",     // quit when done
            "-loglevel", "quiet",
            url.path
        ]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { @Sendable [weak self] terminatedProc in
            ProcessTracker.shared.unregister(terminatedProc)
            if accessing { url.stopAccessingSecurityScopedResource() }
            Task { @MainActor [weak self] in
                guard let self, self.playingTrackID == trackID else { return }
                self.playingTrackID = nil
                self.process = nil
            }
        }

        do {
            try proc.run()
            ProcessTracker.shared.register(proc)
            self.process = proc
            self.playingTrackID = trackID
        } catch {
            if accessing { url.stopAccessingSecurityScopedResource() }
            self.process = nil
            self.playingTrackID = nil
        }
    }
}
