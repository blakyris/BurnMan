import SwiftUI

struct BurnProgressView: View {
    let progress: BurnProgress
    let tracks: [TrackInfo]
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil
    @State private var showTrackDetail = false

    var body: some View {
        VStack(spacing: 16) {
            // Phase label
            HStack {
                phaseIcon
                Text(progress.phase.displayName)
                    .font(.headline)
                Spacer()
                Text(progress.elapsedFormatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Progress bar
            if progress.totalMB > 0 {
                VStack(spacing: 8) {
                    ProgressView(value: progress.percentage, total: 100)
                        .tint(progressColor)

                    HStack {
                        Text("Piste \(progress.currentTrack)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Spacer()

                        Text("\(progress.currentMB) / \(progress.totalMB) Mo")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)

                        Text("(\(String(format: "%.1f", progress.percentage))%)")
                            .font(.system(.caption, design: .monospaced))
                            .fontWeight(.medium)

                        if progress.etaSeconds > 0 {
                            Text("ETA \(progress.etaFormatted)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.orange)
                        }
                    }

                    if progress.bufferFillFIFO > 0 || progress.bufferFillDrive > 0 {
                        HStack(spacing: 12) {
                            Text("FIFO \(progress.bufferFillFIFO)%")
                            Text("Drive \(progress.bufferFillDrive)%")
                            if let speed = progress.writeSpeed {
                                Text(speed)
                            }
                            if progress.isSimulation {
                                Text("SIMULATION")
                                    .fontWeight(.bold)
                                    .foregroundStyle(.blue)
                            }
                        }
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    }
                }
            } else if progress.phase.isActive {
                ProgressView()
                    .scaleEffect(0.8)
            }

            // Track detail
            if !tracks.isEmpty && progress.phase != .idle {
                trackDetailSection
            }

            // Completion badge
            if case .completed = progress.phase {
                CompletionBadge(
                    message: "Gravure terminée en \(progress.elapsedFormatted)",
                    onDismiss: onDismiss
                )
            }

            // Error badge
            if case .failed(let message) = progress.phase {
                ErrorBadge(
                    message: message,
                    onRetry: onRetry,
                    onDismiss: onDismiss
                )
            }

            // Warnings badge
            if !progress.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Avertissements", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    ForEach(progress.warnings, id: \.self) { warning in
                        Text(warning)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .statusBadge(color: .orange)
            }
        }
    }

    // MARK: - Phase Icon

    @ViewBuilder
    private var phaseIcon: some View {
        switch progress.phase {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .preparing, .calibrating:
            Image(systemName: "gear")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, isActive: true)
        case .starting:
            Image(systemName: "bolt.fill")
                .foregroundStyle(.blue)
                .symbolEffect(.pulse, isActive: true)
        case .pausing:
            Image(systemName: "pause.circle")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .blanking:
            Image(systemName: "eraser.fill")
                .foregroundStyle(.purple)
                .symbolEffect(.rotate, isActive: true)
        case .writingLeadIn, .writingLeadOut:
            Image(systemName: "arrow.trianglehead.2.counterclockwise")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, isActive: true)
        case .writingTrack:
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .flushing:
            Image(systemName: "arrow.down.to.line")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Track Detail

    private enum TrackBurnStatus {
        case completed, writing, pending
    }

    private func trackStatus(for trackNumber: Int) -> TrackBurnStatus {
        switch progress.phase {
        case .writingLeadOut, .flushing, .completed:
            return .completed
        default:
            if trackNumber < progress.currentTrack {
                return .completed
            } else if trackNumber == progress.currentTrack {
                return .writing
            } else {
                return .pending
            }
        }
    }

    private var completedTrackCount: Int {
        tracks.filter { trackStatus(for: $0.number) == .completed }.count
    }

    private var trackDetailSection: some View {
        DisclosureGroup(isExpanded: $showTrackDetail) {
            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    trackRow(track)
                    if track.id != tracks.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Label {
                Text("Pistes (\(completedTrackCount)/\(tracks.count))")
            } icon: {
                Image(systemName: "music.note.list")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func trackRow(_ track: TrackInfo) -> some View {
        let status = trackStatus(for: track.number)

        HStack(spacing: 10) {
            // Status icon
            switch status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .writing:
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: true)
            case .pending:
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }

            // Track number
            Text(String(format: "%02d", track.number))
                .font(.system(.caption, design: .monospaced))
                .fontWeight(.bold)

            // Mode badge
            Label(track.mode.displayName, systemImage: track.mode.icon)
                .font(.caption2)
                .trackModeBadge(mode: track.mode)

            // File name
            Text(track.fileName)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            // Size
            Text(String(format: "%.1f Mo", track.sizeMB))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .opacity(status == .pending ? 0.6 : 1.0)
    }

    // MARK: - Colors

    private var progressColor: Color {
        switch progress.phase {
        case .completed: return .green
        case .failed: return .red
        default: return .orange
        }
    }
}
