import SwiftUI

struct DVDAudioSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note.tv")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("DVD Audio")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
