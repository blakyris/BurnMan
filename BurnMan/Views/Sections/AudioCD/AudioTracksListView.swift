import SwiftUI
import UniformTypeIdentifiers

struct AudioTracksListView: View {
    let onOpenFilePicker: () -> Void

    @Environment(AudioCDManager.self) private var audioCDManager
    @Environment(MediaPlayerService.self) private var mediaPlayer
    @State private var selection: Set<AudioTrack.ID> = []
    @State private var sortOrder = [KeyPathComparator<AudioTrack>]()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Audio Tracks", systemImage: "music.note.list")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            if audioCDManager.tracks.isEmpty {
                EmptyDropZone(
                    icon: "music.note",
                    title: "Add audio files",
                    subtitle: "MP3, AAC, FLAC, WAV, AIFF — or drag and drop here",
                    onAdd: { onOpenFilePicker() }
                )
            } else {
                VStack(spacing: 0) {
                    tracksTable

                    TableBottomBar(
                        onAdd: { onOpenFilePicker() },
                        onRemove: {
                            let offsets = IndexSet(
                                audioCDManager.tracks.indices.filter { selection.contains(audioCDManager.tracks[$0].id) }
                            )
                            audioCDManager.removeTrack(at: offsets)
                            selection.removeAll()
                        },
                        removeDisabled: selection.isEmpty
                    )
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(.separator)
                )
            }
        }
        .fileDrop(extensions: ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif"]) { urls in
            Task {
                await audioCDManager.addFiles(urls: urls)
            }
        }
    }

    // MARK: - Table

    private var tracksTable: some View {
        Table(of: AudioTrack.self, selection: $selection, sortOrder: $sortOrder) {
            columns
        } rows: {
            rows
        }
        .tableStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(height: 10 * 28)
        .contextMenu(forSelectionType: AudioTrack.ID.self) { selectedIDs in
            contextMenuItems(for: selectedIDs)
        } primaryAction: { selectedIDs in
            guard let trackID = selectedIDs.first,
                  let track = audioCDManager.tracks.first(where: { $0.id == trackID })
            else { return }
            mediaPlayer.toggle(trackID: track.id, url: track.sourceURL,
                               title: track.title, artist: track.artist,
                               duration: track.durationSeconds)
        }
        .onChange(of: sortOrder) { _, newOrder in
            audioCDManager.sortTracks(using: newOrder)
        }
    }

    // MARK: - Columns

    @TableColumnBuilder<AudioTrack, KeyPathComparator<AudioTrack>>
    private var columns: some TableColumnContent<AudioTrack, KeyPathComparator<AudioTrack>> {
        TableColumn("#", value: \.order) { (track: AudioTrack) in
            Text(String(format: "%02d", track.order))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .width(min: 30, ideal: 36, max: 44)

        TableColumn("Title", value: \.title)
            .width(min: 100, ideal: 200)

        TableColumn("Artist", value: \.artist)
            .width(min: 80, ideal: 140)

        TableColumn("Album", value: \.albumName)
            .width(min: 80, ideal: 140)

        TableColumn("Duration", value: \.durationSeconds) { (track: AudioTrack) in
            Text(track.durationFormatted)
                .font(.system(.body, design: .monospaced))
        }
        .width(min: 50, ideal: 56, max: 64)

        TableColumn("Format", value: \.sourceFormat) { (track: AudioTrack) in
            Text(track.sourceFormat)
                .font(.caption2).fontWeight(.medium)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(
                    (track.needsConversion ? Color.orange : Color.green).opacity(0.15),
                    in: .capsule
                )
                .foregroundStyle(track.needsConversion ? .orange : .green)
        }
        .width(min: 50, ideal: 60, max: 72)
    }

    // MARK: - Rows

    @TableRowBuilder<AudioTrack>
    private var rows: some TableRowContent<AudioTrack> {
        ForEach(audioCDManager.tracks) { track in
            TableRow(track)
                .draggable(AudioTrackTransfer(id: track.id))
        }
        .onInsert(of: [.audioTrackID]) { offset, providers in
            guard let provider = providers.first else { return }
            Task { @MainActor in
                if let data = try? await provider.loadItem(forTypeIdentifier: UTType.audioTrackID.identifier) as? Data,
                   let transfer = try? JSONDecoder().decode(AudioTrackTransfer.self, from: data),
                   let sourceIndex = audioCDManager.tracks.firstIndex(where: { $0.id == transfer.id }) {
                    audioCDManager.moveTrack(from: IndexSet(integer: sourceIndex), to: offset)
                }
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func contextMenuItems(for selectedIDs: Set<AudioTrack.ID>) -> some View {
        let selectedTracks = audioCDManager.tracks.filter { selectedIDs.contains($0.id) }

        if selectedTracks.count == 1, let track = selectedTracks.first {
            let isPlaying = mediaPlayer.playingTrackID == track.id
            Button {
                mediaPlayer.toggle(trackID: track.id, url: track.sourceURL,
                                   title: track.title, artist: track.artist,
                                   duration: track.durationSeconds)
            } label: {
                Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause" : "play")
            }

            Divider()

            if let index = audioCDManager.tracks.firstIndex(where: { $0.id == track.id }) {
                Button {
                    audioCDManager.moveTrack(from: IndexSet(integer: index), to: max(0, index - 1))
                } label: {
                    Label("Move Up", systemImage: "arrow.up")
                }
                .disabled(index == 0)

                Button {
                    audioCDManager.moveTrack(from: IndexSet(integer: index), to: min(audioCDManager.tracks.count, index + 2))
                } label: {
                    Label("Move Down", systemImage: "arrow.down")
                }
                .disabled(index >= audioCDManager.tracks.count - 1)

                Divider()
            }
        }

        Button(role: .destructive) {
            let offsets = IndexSet(
                audioCDManager.tracks.indices.filter { selectedIDs.contains(audioCDManager.tracks[$0].id) }
            )
            audioCDManager.removeTrack(at: offsets)
            selection.removeAll()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
