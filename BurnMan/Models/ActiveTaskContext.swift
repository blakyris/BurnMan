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
    var isRunning: Bool = false
    var progress: Double? = nil
    var statusText: String = ""

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
}
