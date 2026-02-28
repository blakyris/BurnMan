import Foundation
import VLCKit

/// Manages audio and video preview playback via VLCKit.
/// Only @Observable service — owns playback state.
@MainActor
@Observable
class MediaPlayerService {
    /// ID of the track currently playing (nil if stopped).
    private(set) var playingTrackID: UUID?
    private(set) var playingURL: URL?
    private(set) var isPlaying = false
    private(set) var playingTrackTitle: String?
    private(set) var playingTrackArtist: String?
    private(set) var trackDuration: Double = 0
    private(set) var playbackElapsed: Double = 0

    var playbackProgress: Double {
        guard trackDuration > 0 else { return 0 }
        return min(max(playbackElapsed / trackDuration, 0), 1)
    }

    /// Called when a track finishes playing normally.
    /// Set this to enable auto-advance to the next track.
    var onTrackFinished: (() -> Void)?

    private var vlcPlayer: VLCMediaPlayer?
    private var vlcDelegate: PlayerDelegate?
    private var timerTask: Task<Void, Never>?

    // MARK: - Audio Playback

    /// Plays an audio file via VLCKit.
    func playAudio(trackID: UUID, url: URL, title: String? = nil, artist: String? = nil, duration: Double = 0) {
        stop()

        let media = VLCMedia(url: url)
        media.addOption(":file-caching=1000")

        let player = VLCMediaPlayer()
        player.media = media

        let delegate = PlayerDelegate { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let callback = self.onTrackFinished
                self.stop()
                callback?()
            }
        }
        player.delegate = delegate
        self.vlcDelegate = delegate

        player.play()
        self.vlcPlayer = player
        self.playingTrackID = trackID
        self.playingURL = url
        self.isPlaying = true
        self.playingTrackTitle = title
        self.playingTrackArtist = artist
        self.trackDuration = duration
        self.playbackElapsed = 0
        startTimer()
    }

    // MARK: - Video Playback

    /// Returns a VLCMediaPlayer for any video file (all formats supported natively).
    func playVideo(url: URL) -> VLCMediaPlayer {
        stop()
        let media = VLCMedia(url: url)
        let player = VLCMediaPlayer()
        player.media = media
        player.play()
        self.vlcPlayer = player
        self.isPlaying = true
        return player
    }

    // MARK: - Controls

    /// Toggle play/stop for a given track.
    func toggle(trackID: UUID, url: URL, title: String? = nil, artist: String? = nil, duration: Double = 0) {
        if playingTrackID == trackID {
            stop()
        } else {
            playAudio(trackID: trackID, url: url, title: title, artist: artist, duration: duration)
        }
    }

    func pause() {
        vlcPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func resume() {
        vlcPlayer?.play()
        isPlaying = true
        startTimer()
    }

    func seek(to seconds: Double) {
        guard vlcPlayer != nil else { return }
        vlcPlayer?.time = VLCTime(int: Int32(seconds * 1000))
        playbackElapsed = seconds
    }

    func stop() {
        stopTimer()
        vlcPlayer?.stop()
        vlcPlayer = nil
        vlcDelegate = nil
        playingTrackID = nil
        playingURL = nil
        isPlaying = false
        playingTrackTitle = nil
        playingTrackArtist = nil
        trackDuration = 0
        playbackElapsed = 0
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled, let self, self.isPlaying,
                      let time = self.vlcPlayer?.time else { break }
                let newElapsed = Double(time.intValue) / 1000.0
                if Int(newElapsed) != Int(self.playbackElapsed) {
                    self.playbackElapsed = newElapsed
                }
            }
        }
    }

    private func stopTimer() {
        timerTask?.cancel()
        timerTask = nil
    }
}

// MARK: - VLCMediaPlayerDelegate

private final class PlayerDelegate: NSObject, VLCMediaPlayerDelegate {
    let onFinished: () -> Void

    init(onFinished: @escaping () -> Void) {
        self.onFinished = onFinished
    }

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        guard let player = aNotification.object as? VLCMediaPlayer else { return }
        if player.state == .ended {
            onFinished()
        }
    }
}
