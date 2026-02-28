import SwiftUI

/// Shared progress/status section for views that use `PipelineState`.
///
/// Handles `.finished` → `CompletionBadge`, `.failed` → `ErrorBadge`,
/// and all other states → `ProgressView` + `displayName`.
///
/// For states that need a determinate progress bar (e.g. `.extracting`, `.converting`),
/// pass `progress` to show a `ProgressView(value:)` instead of an indeterminate spinner.
struct PipelineStatusView: View {
    let state: PipelineState
    let error: String?
    let completionMessage: String
    var progress: Double? = nil

    var body: some View {
        SectionContainer(title: "Progress", systemImage: "waveform.path") {
            VStack(spacing: 8) {
                switch state {
                case .finished:
                    CompletionBadge(message: completionMessage)
                case .failed:
                    if let error {
                        ErrorBadge(message: error)
                    }
                default:
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(state.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
