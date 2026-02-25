import SwiftUI

struct ConvertDiscImageSection: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text("Disc Image Conversion")
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
