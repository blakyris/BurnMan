import SwiftUI

/// Reusable empty-state drop zone used across all file-based sections.
struct EmptyDropZone: View {
    let icon: String
    let title: String
    let subtitle: String
    var buttonLabel: String = "Add Files"
    var showsBackground: Bool = true
    var padding: CGFloat = 24
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button(buttonLabel) {
                onAdd()
            }
            .buttonStyle(.glass)
        }
        .frame(maxWidth: .infinity)
        .padding(padding)
        .modifier(ConditionalBackgroundModifier(showsBackground: showsBackground))
    }
}

// MARK: - Conditional Background

private struct ConditionalBackgroundModifier: ViewModifier {
    let showsBackground: Bool

    func body(content: Content) -> some View {
        if showsBackground {
            content
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            content
        }
    }
}
