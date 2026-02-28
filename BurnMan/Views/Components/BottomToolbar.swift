import SwiftUI

struct BottomToolbar: View {
    @Environment(ActiveTaskContext.self) private var taskContext
    @Environment(DeviceManager.self) private var deviceManager
    @Environment(MediaPlayerService.self) private var mediaPlayer

    @State private var showDetailPopover = false

    var body: some View {
        VStack(spacing: 0) {
            if taskContext.isRunning {
                runningContent
            } else {
                HStack(spacing: 16) {
                    if taskContext.hasResult {
                        resultContent
                    } else {
                        idleContent
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .background(.bar)
    }

    // MARK: - Idle State

    private var idleContent: some View {
        Group {
            // Mini Player
            if mediaPlayer.playingTrackID != nil {
                MiniPlayerView()
            }

            Spacer()

            // Device Picker + Action Buttons
            DevicePickerView()

            if let simulate = taskContext.onSimulate {
                Button("Simulate", action: simulate)
                    .disabled(!taskContext.canExecute)
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if let execute = taskContext.onExecute {
                Button(taskContext.actionLabel, action: execute)
                    .disabled(!taskContext.canExecute)
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: - Running State

    private var runningContent: some View {
        VStack(spacing: 4) {
            // Top row: status label left, percentage + time + buttons right
            HStack(spacing: 8) {
                if !taskContext.statusText.isEmpty {
                    Text(taskContext.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let progress = taskContext.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(.callout, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                if !taskContext.elapsedFormatted.isEmpty {
                    Text(taskContext.elapsedFormatted)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                detailButton

                if let cancel = taskContext.onCancel {
                    Button("Cancel", role: .destructive, action: cancel)
                        .controlSize(.small)
                        .buttonStyle(.bordered)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            // Full-width progress bar
            if let progress = taskContext.progress {
                ProgressView(value: progress)
                    .tint(.orange)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Result State

    private var resultContent: some View {
        Group {
            switch taskContext.result {
            case .completed(let message):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
                Text(message)
                    .font(.callout)
                    .fontWeight(.medium)

            case .failed(let message):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)

            case .none:
                EmptyView()
            }

            Spacer()

            // Detail popover button
            detailButton

            // Retry button (failed only)
            if case .failed = taskContext.result, let retry = taskContext.onRetry {
                Button("Retry", action: retry)
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Dismiss button
            if let dismiss = taskContext.onDismissResult {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .clipShape(Circle())
            }
        }
    }

    // MARK: - Detail Popover

    private var detailButton: some View {
        Group {
            if taskContext.detailPayload != nil {
                Button {
                    showDetailPopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                }
                .buttonStyle(.borderless)
                .popover(isPresented: $showDetailPopover) {
                    if let payload = taskContext.detailPayload {
                        BurnDetailPopover(payload: payload)
                    }
                }
            }
        }
    }
}
