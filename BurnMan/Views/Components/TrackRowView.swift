import SwiftUI

struct TrackRowView: View {
    let track: TrackInfo
    var showDuration = false
    var showMSF = false
    var showFileName = true

    var body: some View {
        HStack(spacing: 12) {
            Text(String(format: "%02d", track.number))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)
                .foregroundStyle(.secondary)

            Label(track.mode.displayName, systemImage: track.mode.icon)
                .font(.caption)
                .trackModeBadge(mode: track.mode)

            Spacer()

            if showDuration {
                Text(track.durationFormatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if showMSF {
                Text("@ \(track.msfStart)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            if showFileName {
                Text(track.fileName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text(String(format: "%.1f Mo", track.sizeMB))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
    }
}
