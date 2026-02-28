import SwiftUI

struct BurnDetailPopover: View {
    let payload: DetailPayload

    var body: some View {
        switch payload {
        case .audioCDBurn(let progress, let tracks):
            audioCDContent(progress: progress, tracks: tracks)
        case .dataCDBurn(let progress):
            dataCDContent(progress: progress)
        }
    }

    // MARK: - Audio CD Content

    private func audioCDContent(progress: AudioCDProgress, tracks: [AudioTrack]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phase header
            HStack(spacing: 6) {
                audioCDPhaseIcon(progress: progress)
                Text(progress.pipelinePhase.displayName)
                    .font(.headline)
                Spacer()
                Text(progress.elapsedFormatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Track list with status
            if !tracks.isEmpty {
                audioCDTrackList(progress: progress, tracks: tracks)
            }

            // Buffer & speed info during burn
            if case .burning = progress.pipelinePhase, progress.totalMB > 0 {
                audioCDBurnStats(progress: progress)
            }

            // Warnings
            if !progress.warnings.isEmpty {
                audioCDWarningsList(progress: progress)
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    // MARK: - Data CD Content

    private func dataCDContent(progress: DataCDProgress) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Phase header
            HStack(spacing: 6) {
                dataCDPhaseIcon(progress: progress)
                Text(progress.phase.displayName)
                    .font(.headline)
                Spacer()
                Text(progress.elapsedFormatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Progress bars per phase
            VStack(alignment: .leading, spacing: 8) {
                if progress.isoPercent > 0 {
                    HStack {
                        Text("ISO")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        ProgressView(value: progress.isoPercent, total: 100)
                        Text("\(Int(progress.isoPercent))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                if progress.burnPercent > 0 {
                    HStack {
                        Text("Burn")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 50, alignment: .leading)
                        ProgressView(value: progress.burnPercent, total: 100)
                        Text("\(Int(progress.burnPercent))%")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Stats
            HStack(spacing: 12) {
                if progress.fifoPercent > 0 {
                    Label("FIFO \(progress.fifoPercent)%", systemImage: "memorychip")
                }
                if let speed = progress.writeSpeed {
                    Label(speed, systemImage: "speedometer")
                }
                if progress.isSimulation {
                    Text("SIMULATION")
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                }
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)

            // Warnings
            if !progress.warnings.isEmpty {
                Divider()
                Label("Warnings", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                ForEach(progress.warnings, id: \.self) { warning in
                    Text(warning)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .frame(width: 320)
    }

    // MARK: - Audio CD Phase Icon

    @ViewBuilder
    private func audioCDPhaseIcon(progress: AudioCDProgress) -> some View {
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

    // MARK: - Audio CD Track List

    private func audioCDTrackList(progress: AudioCDProgress, tracks: [AudioTrack]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tracks")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)

            ForEach(Array(tracks.enumerated()), id: \.offset) { entry in
                let track = entry.element
                HStack(spacing: 6) {
                    audioCDTrackStatusIcon(for: entry.offset + 1, progress: progress)
                        .frame(width: 14)

                    Text(String(format: "%02d", track.order))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Text(track.title)
                        .font(.caption)
                        .lineLimit(1)

                    Spacer()

                    Text(track.durationFormatted)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func audioCDTrackStatusIcon(for trackNumber: Int, progress: AudioCDProgress) -> some View {
        switch progress.pipelinePhase {
        case .converting(let current, _):
            if trackNumber < current {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if trackNumber == current {
                Image(systemName: "waveform")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: true)
            } else {
                Image(systemName: "circle")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        case .burning:
            if trackNumber < progress.currentTrack {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
            } else if trackNumber == progress.currentTrack {
                Image(systemName: "flame.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse, isActive: true)
            } else {
                Image(systemName: "circle")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
            }
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        default:
            Image(systemName: "circle")
                .font(.caption2)
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Audio CD Burn Stats

    private func audioCDBurnStats(progress: AudioCDProgress) -> some View {
        VStack(spacing: 6) {
            Divider()

            HStack {
                Text("Track \(progress.currentTrack)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(progress.currentMB) / \(progress.totalMB) MB")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if progress.bufferFillFIFO > 0 || progress.bufferFillDrive > 0 {
                    Label("FIFO \(progress.bufferFillFIFO)%", systemImage: "memorychip")
                    Label("Drive \(progress.bufferFillDrive)%", systemImage: "externaldrive")
                }
                if let speed = progress.writeSpeed {
                    Label(speed, systemImage: "speedometer")
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

    // MARK: - Audio CD Warnings

    private func audioCDWarningsList(progress: AudioCDProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()

            Label("Warnings", systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.orange)

            ForEach(progress.warnings, id: \.self) { warning in
                Text(warning)
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Data CD Phase Icon

    @ViewBuilder
    private func dataCDPhaseIcon(progress: DataCDProgress) -> some View {
        switch progress.phase {
        case .idle:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .validating:
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, isActive: true)
        case .creatingISO:
            Image(systemName: "doc.zipper")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .burning:
            Image(systemName: "flame.fill")
                .foregroundStyle(.orange)
                .symbolEffect(.pulse, isActive: true)
        case .verifying:
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.blue)
                .symbolEffect(.rotate, isActive: true)
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
}
