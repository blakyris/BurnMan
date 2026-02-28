import SwiftUI

struct MiniPlayerView: View {
    @Environment(MediaPlayerService.self) private var mediaPlayer
    @Environment(AudioCDManager.self) private var audioCDManager

    var body: some View {
        HStack(spacing: 10) {
            // Transport controls
            HStack(spacing: 8) {
                Button { playPrevious() } label: {
                    Image(systemName: "backward.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .disabled(!canGoPrevious)

                Button {
                    if mediaPlayer.isPlaying {
                        mediaPlayer.pause()
                    } else {
                        mediaPlayer.resume()
                    }
                } label: {
                    Image(systemName: mediaPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)

                Button { mediaPlayer.stop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)

                Button { playNext() } label: {
                    Image(systemName: "forward.fill")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .disabled(!canGoNext)
            }

            Divider()
                .frame(height: 24)

            // Track info + seekable progress bar
            VStack(alignment: .leading, spacing: 3) {
                // Title — Artist + elapsed time
                HStack(spacing: 0) {
                    trackInfoText
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    Text(formatTime(mediaPlayer.playbackElapsed))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Seekable progress bar
                SeekableProgressBar(
                    progress: mediaPlayer.playbackProgress,
                    onSeek: { ratio in
                        let target = ratio * mediaPlayer.trackDuration
                        mediaPlayer.seek(to: target)
                    }
                )
                .frame(height: 4)
            }
            .frame(minWidth: 160, maxWidth: .infinity)
        }
        .onAppear { setupAutoAdvance() }
        .onChange(of: mediaPlayer.playingTrackID) { setupAutoAdvance() }
    }

    @ViewBuilder
    private var trackInfoText: some View {
        let title = mediaPlayer.playingTrackTitle ?? ""
        let artist = mediaPlayer.playingTrackArtist ?? ""

        if !title.isEmpty, !artist.isEmpty {
            Text("\(Text(title).fontWeight(.bold)) — \(artist)")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if !title.isEmpty {
            Text(title).font(.caption).fontWeight(.bold)
        } else {
            Text("").font(.caption)
        }
    }

    // MARK: - Navigation

    private var currentIndex: Int? {
        guard let id = mediaPlayer.playingTrackID else { return nil }
        return audioCDManager.tracks.firstIndex(where: { $0.id == id })
    }

    private var canGoPrevious: Bool {
        guard let index = currentIndex else { return false }
        return index > 0
    }

    private var canGoNext: Bool {
        guard let index = currentIndex else { return false }
        return index < audioCDManager.tracks.count - 1
    }

    private func playPrevious() {
        guard let index = currentIndex, index > 0 else { return }
        let track = audioCDManager.tracks[index - 1]
        mediaPlayer.playAudio(trackID: track.id, url: track.sourceURL,
                              title: track.title, artist: track.artist,
                              duration: track.durationSeconds)
    }

    private func playNext() {
        guard let index = currentIndex, index < audioCDManager.tracks.count - 1 else { return }
        let track = audioCDManager.tracks[index + 1]
        mediaPlayer.playAudio(trackID: track.id, url: track.sourceURL,
                              title: track.title, artist: track.artist,
                              duration: track.durationSeconds)
    }

    private func setupAutoAdvance() {
        mediaPlayer.onTrackFinished = { [self] in
            playNext()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Double) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

// MARK: - SeekableProgressBar

private struct SeekableProgressBar: View {
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.primary.opacity(0.15))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: geo.size.width * max(0, min(progress, 1)))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let ratio = max(0, min(value.location.x / geo.size.width, 1))
                            onSeek(ratio)
                        }
                )
        }
    }
}
