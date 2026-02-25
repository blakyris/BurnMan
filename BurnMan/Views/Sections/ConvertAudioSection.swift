import SwiftUI

struct ConvertAudioSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Audio Conversion")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text("Coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
    }
}
