import Foundation

/// Polls a log file for new content at regular intervals.
/// Used for reading helper IPC log files that the root helper writes to.
@MainActor
final class LogFilePoller {
    private var task: Task<Void, Never>?
    private var lastOffset: UInt64 = 0

    /// Starts polling `logPath` every `interval`.
    /// Calls `onLines` on MainActor for each batch of new lines.
    func start(
        logPath: String,
        interval: Duration = .milliseconds(500),
        onLines: @escaping @MainActor ([String]) -> Void
    ) {
        lastOffset = 0
        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard let self else { return }
                let lines = self.readNewLines(logPath: logPath)
                if !lines.isEmpty { onLines(lines) }
            }
        }
    }

    /// Stops polling and performs a final read to capture any remaining output.
    func stop(logPath: String, onLines: (([String]) -> Void)? = nil) {
        task?.cancel()
        task = nil
        let remaining = readNewLines(logPath: logPath)
        if !remaining.isEmpty { onLines?(remaining) }
    }

    private func readNewLines(logPath: String) -> [String] {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return [] }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastOffset)
        let data = handle.readDataToEndOfFile()
        lastOffset = handle.offsetInFile

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return [] }

        return text.components(separatedBy: "\n").filter { !$0.isEmpty }
    }
}
