import SwiftUI

// MARK: - Section Container (replaces GroupBox)

struct SectionContainer<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            content
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.3))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Setting Row

struct SettingRow<Control: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}

// MARK: - Completion Badge

struct CompletionBadge: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title2)
            Text(message)
                .font(.subheadline)
                .fontWeight(.medium)

            Spacer()

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .statusBadge(color: .green)
    }
}

// MARK: - Error Badge

struct ErrorBadge: View {
    let message: String
    var onRetry: (() -> Void)? = nil
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title2)
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)

            Spacer()

            if let onRetry {
                Button {
                    onRetry()
                } label: {
                    Label("Réessayer", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.glass)
            }

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.glass)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .statusBadge(color: .red)
    }
}

// MARK: - Glass Modifiers

extension View {
    func statusBadge(color: Color) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(color), in: .rect(cornerRadius: 10))
    }

    func trackModeBadge(mode: TrackMode) -> some View {
        let color: Color = mode == .audio ? .green : .blue
        return self
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(color), in: .capsule)
    }

    func successToastStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.green), in: .capsule)
    }

    func dropHighlight(isTargeted: Bool) -> some View {
        self.overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.blue, lineWidth: 2)
            }
        }
    }
}
