import SwiftUI

/// Shared context that drives the BottomToolbar and menu commands.
///
/// Each section updates this when it becomes the active section,
/// wiring its own callbacks and state into the shared toolbar.
@MainActor @Observable
final class ActiveTaskContext {
    // MARK: - Identity
    var actionLabel: String = "Burn"
    var actionIcon: String = "flame"

    // MARK: - State
    var canExecute: Bool = false
    var progress: Double? = nil
    var statusText: String = ""

    /// Setting `isRunning` automatically starts/stops the elapsed timer.
    var isRunning: Bool = false {
        didSet {
            guard isRunning != oldValue else { return }
            if isRunning {
                startElapsedTimer()
            } else {
                stopElapsedTimer()
            }
        }
    }

    // MARK: - Progress Detail
    var currentMB: Int = 0
    var totalMB: Int = 0
    var elapsedFormatted: String = ""
    var detailPayload: DetailPayload?

    // MARK: - Elapsed Timer

    private var elapsedTask: Task<Void, Never>?
    private var elapsedStart: Date?

    private func startElapsedTimer() {
        elapsedStart = Date()
        elapsedFormatted = "0:00"
        elapsedTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let start = self.elapsedStart else { return }
                let elapsed = Int(Date().timeIntervalSince(start))
                self.elapsedFormatted = String(format: "%d:%02d", elapsed / 60, elapsed % 60)
            }
        }
    }

    private func stopElapsedTimer() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    // MARK: - Result
    enum TaskResult: Equatable {
        case none
        case completed(String)
        case failed(String)
    }
    var result: TaskResult = .none
    var warnings: [String] = []
    var onDismissResult: (() -> Void)?
    var onRetry: (() -> Void)?

    // MARK: - Callbacks
    var onExecute: (() -> Void)?
    var onSimulate: (() -> Void)?
    var onCancel: (() -> Void)?
    var onAddFiles: (() -> Void)?
    var onOpenCue: (() -> Void)?
    var onSaveCue: (() -> Void)?

    // MARK: - Log
    var showLog: Bool = false
    var logEntries: [String] = []

    /// Whether the toolbar should show result state (completed or failed).
    var hasResult: Bool {
        result != .none
    }

    /// Reset result state to return toolbar to normal.
    func clearResult() {
        result = .none
        warnings = []
        detailPayload = nil
        currentMB = 0
        totalMB = 0
        elapsedFormatted = ""
    }

    // MARK: - Binding

    /// Binds a section's actions and state to the shared toolbar.
    func bind(_ binding: TaskBinding) {
        actionLabel = binding.actionLabel
        actionIcon = binding.actionIcon
        canExecute = binding.canExecute
        isRunning = binding.isRunning
        onExecute = binding.onExecute
        onSimulate = binding.onSimulate
        onCancel = binding.onCancel
        onAddFiles = binding.onAddFiles
        onOpenCue = binding.onOpenCue
        onSaveCue = binding.onSaveCue
        statusText = binding.statusText
    }
}

// MARK: - Detail Payload

/// Type-erased payload for the detail popover in BottomToolbar.
enum DetailPayload {
    case audioCDBurn(progress: AudioCDProgress, tracks: [AudioTrack])
    case dataCDBurn(progress: DataCDProgress)
}

// MARK: - Task Binding

/// Configuration that a section view passes to `ActiveTaskContext.bind()`.
struct TaskBinding {
    var actionLabel: String = "Burn"
    var actionIcon: String = "flame"
    var canExecute: Bool = false
    var isRunning: Bool = false
    var onExecute: (() -> Void)?
    var onSimulate: (() -> Void)?
    var onCancel: (() -> Void)?
    var onAddFiles: (() -> Void)?
    var onOpenCue: (() -> Void)?
    var onSaveCue: (() -> Void)?
    var statusText: String = ""
}
