import SwiftUI

struct AudioCDTextEditor: View {
    @Environment(AudioCDManager.self) private var audioCDManager

    var body: some View {
        @Bindable var audioCDManager = audioCDManager

        SectionContainer(title: "Metadata", systemImage: "text.quote") {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    Button {
                        Task { await audioCDManager.fillMetadataFromFiles() }
                    } label: {
                        Label("Autofill metadata", systemImage: "arrow.down.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)

                    Button {
                    } label: {
                        Label("Search metadata", systemImage: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.glass)
                    .disabled(true)

                    Spacer()
                }

                DisclosureGroup("Edit Metadata") {
                    VStack(spacing: 16) {
                        VStack(spacing: 10) {
                            Text("Disc")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            HStack(spacing: 12) {
                                cdTextField("Album Title", text: $audioCDManager.cdText.albumTitle)
                                cdTextField("Artist", text: $audioCDManager.cdText.albumArtist)
                            }

                            HStack(spacing: 12) {
                                cdTextField("Songwriter", text: $audioCDManager.cdText.albumSongwriter)
                                cdTextField("Message", text: $audioCDManager.cdText.albumMessage)
                            }

                            HStack(spacing: 12) {
                                cdTextField("UPC/EAN", text: $audioCDManager.cdText.upcEan)
                                Spacer()
                            }
                        }

                        Divider()

                        VStack(spacing: 10) {
                            Text("Tracks")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach($audioCDManager.tracks) { $track in
                                DisclosureGroup {
                                    VStack(spacing: 8) {
                                        HStack(spacing: 12) {
                                            cdTextField("Title", text: $track.title)
                                            cdTextField("Artist", text: $track.artist)
                                        }
                                        HStack(spacing: 12) {
                                            cdTextField("Songwriter", text: $track.songwriter)
                                            cdTextField("ISRC", text: $track.isrc)
                                        }
                                        cdTextField("Message", text: $track.message)
                                    }
                                    .padding(.top, 4)
                                } label: {
                                    HStack(spacing: 8) {
                                        Text(String(format: "%02d", track.order))
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(.medium)
                                            .foregroundStyle(.secondary)
                                            .frame(width: 20)
                                        Text(track.title)
                                            .font(.caption)
                                            .lineLimit(1)
                                        if !track.artist.isEmpty {
                                            Text("—")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                            Text(track.artist)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .font(.caption)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
        }
    }

    private func cdTextField(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }
}
