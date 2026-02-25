import SwiftUI

struct ConvertFileSection: View {
    var body: some View {
        placeholderContent(title: "File Conversion", icon: "doc.arrow.triangle.2.circlepath")
    }

    private func placeholderContent(title: String, icon: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(title)
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
