import SwiftUI

struct AudioTrackRowView: View {
    let track: AudioTrack
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onRemove: (() -> Void)?
    @Environment(AudioPreviewPlayer.self) private var previewPlayer

    private var isPlaying: Bool {
        previewPlayer.playingTrackID == track.id
    }

    var body: some View {
        HStack(spacing: 10) {
            // Track number
            Text(String(format: "%02d", track.order))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            // Play/Pause button
            Button {
                previewPlayer.toggle(trackID: track.id, url: track.sourceURL)
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(isPlaying ? .orange : .secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            // Title + Artist
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Format badge
            Text(track.sourceFormat)
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    (track.needsConversion ? Color.orange : Color.green).opacity(0.15),
                    in: .capsule
                )
                .foregroundStyle(track.needsConversion ? .orange : .green)

            // CD-quality indicator
            if track.isCDQuality {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }

            // Duration
            Text(track.durationFormatted)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        
        .contextMenu {
            Button {
                previewPlayer.toggle(trackID: track.id, url: track.sourceURL)
            } label: {
                Label(isPlaying ? "Pause" : "Lecture", systemImage: isPlaying ? "pause" : "play")
            }

            Divider()

            Button {
                onMoveUp?()
            } label: {
                Label("Monter", systemImage: "arrow.up")
            }
            .disabled(onMoveUp == nil)

            Button {
                onMoveDown?()
            } label: {
                Label("Descendre", systemImage: "arrow.down")
            }
            .disabled(onMoveDown == nil)

            Divider()

            Button(role: .destructive) {
                onRemove?()
            } label: {
                Label("Supprimer", systemImage: "trash")
            }
        }
    }
}
