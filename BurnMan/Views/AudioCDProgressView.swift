import SwiftUI

struct AudioCDProgressView: View {
    let progress: AudioCDProgress
    let tracks: [AudioTrack]
    var onDismiss: (() -> Void)? = nil
    var onRetry: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            // Pipeline steps indicator
            pipelineSteps

            // Phase label + elapsed time
            HStack {
                phaseIcon
                Text(progress.pipelinePhase.displayName)
                    .font(.headline)
                Spacer()
                Text(progress.elapsedFormatted)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            // Overall progress bar
            VStack(spacing: 8) {
                ProgressView(value: progress.overallPercentage, total: 100)
                    .tint(progressColor)

                HStack {
                    Text("\(String(format: "%.0f", progress.overallPercentage))%")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)

                    Spacer()

                    phaseDetail
                }
            }

            // Conversion detail
            if case .converting = progress.pipelinePhase {
                conversionDetail
            }

            // Burn detail
            if case .burning = progress.pipelinePhase, progress.totalMB > 0 {
                burnDetail
            }

            // Completion badge
            if case .completed = progress.pipelinePhase {
                CompletionBadge(
                    message: "CD audio gravé en \(progress.elapsedFormatted)",
                    onDismiss: onDismiss
                )
            }

            // Error badge
            if case .failed(let message) = progress.pipelinePhase {
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

    // MARK: - Pipeline Steps

    private let circleSize: CGFloat = 20

    private var pipelineSteps: some View {
        HStack(spacing: 0) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                VStack(spacing: 4) {
                    // Circle row with connector lines
                    HStack(spacing: 0) {
                        // Left connector
                        if index > 0 {
                            Rectangle()
                                .fill(stepCompleted(index) ? Color.green : Color.secondary.opacity(0.3))
                                .frame(height: 2)
                        } else {
                            Color.clear.frame(height: 2)
                        }

                        // Circle
                        ZStack {
                            Circle()
                                .fill(stepColor(index))
                                .frame(width: circleSize, height: circleSize)

                            if stepCompleted(index) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if stepActive(index) {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .fixedSize()

                        // Right connector
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(stepCompleted(index + 1) ? Color.green : Color.secondary.opacity(0.3))
                                .frame(height: 2)
                        } else {
                            Color.clear.frame(height: 2)
                        }
                    }
                    .frame(height: circleSize)

                    Text(step)
                        .font(.caption2)
                        .foregroundStyle(stepActive(index) ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
    }

    private var steps: [String] {
        ["Préparation", "Gravure", "Finalisation"]
    }

    private func stepIndex(for phase: AudioCDPhase) -> Int {
        switch phase {
        case .idle: return -1
        case .validating, .converting, .generatingTOC: return 0
        case .burning: return 1
        case .cleaningUp: return 2
        case .completed: return 3
        case .failed: return -1
        }
    }

    private func stepCompleted(_ index: Int) -> Bool {
        stepIndex(for: progress.pipelinePhase) > index
    }

    private func stepActive(_ index: Int) -> Bool {
        stepIndex(for: progress.pipelinePhase) == index
    }

    private func stepColor(_ index: Int) -> Color {
        if stepCompleted(index) { return .green }
        if stepActive(index) { return .blue }
        return .secondary.opacity(0.3)
    }

    // MARK: - Phase Icon

    @ViewBuilder
    private var phaseIcon: some View {
        switch progress.pipelinePhase {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .validating:
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, isActive: true)
        case .converting:
            Image(systemName: "waveform")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .generatingTOC:
            Image(systemName: "doc.text")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, isActive: true)
        case .burning:
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .cleaningUp:
            Image(systemName: "trash")
                .foregroundStyle(.blue)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    // MARK: - Phase Detail

    @ViewBuilder
    private var phaseDetail: some View {
        switch progress.pipelinePhase {
        case .converting(let cur, let tot):
            Text("Piste \(cur)/\(tot)")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .burning:
            if progress.totalMB > 0 {
                Text("\(progress.currentMB)/\(progress.totalMB) Mo")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Conversion Detail

    private var conversionDetail: some View {
        VStack(spacing: 6) {
            if progress.conversionTrackIndex > 0,
               progress.conversionTrackIndex <= tracks.count {
                let trackIdx = progress.conversionTrackIndex - 1
                Text(tracks[trackIdx].sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ProgressView(value: progress.conversionTrackProgress, total: 1.0)
                .tint(.orange)

            Text("Conversion en WAV PCM 16bit/44.1kHz")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Burn Detail

    private var burnDetail: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Piste \(progress.currentTrack)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.currentMB) / \(progress.totalMB) Mo")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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

            Text(progress.burnPhase.displayName)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.2))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Colors

    private var progressColor: Color {
        switch progress.pipelinePhase {
        case .completed: return .green
        case .failed: return .red
        default: return .orange
        }
    }
}
