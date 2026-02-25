import SwiftUI

struct BottomToolbar: View {
    @Environment(ActiveTaskContext.self) private var taskContext
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        HStack(spacing: 16) {
            // MARK: Left — Device Picker
            DevicePickerView()

            Spacer()

            // MARK: Center — Progress & Status
            if taskContext.isRunning {
                if let progress = taskContext.progress {
                    ProgressView(value: progress)
                        .frame(width: 160)
                    Text("\(Int(progress * 100))%")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 40, alignment: .trailing)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                if !taskContext.statusText.isEmpty {
                    Text(taskContext.statusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // MARK: Right — Action Buttons
            if taskContext.isRunning {
                if let cancel = taskContext.onCancel {
                    Button("Cancel", role: .destructive, action: cancel)
                }
            } else {
                if let simulate = taskContext.onSimulate {
                    Button("Simulate", action: simulate)
                        .disabled(!taskContext.canExecute)
                }
                if let execute = taskContext.onExecute {
                    Button(taskContext.actionLabel, action: execute)
                        .disabled(!taskContext.canExecute)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
