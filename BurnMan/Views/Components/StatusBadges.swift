import SwiftUI

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
                    Label("Retry", systemImage: "arrow.clockwise")
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
