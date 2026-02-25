import SwiftUI

struct ConvertVideoSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "film")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Video Conversion")
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
