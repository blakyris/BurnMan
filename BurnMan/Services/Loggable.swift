import Foundation

/// Protocol for managers that maintain a log of messages.
/// Provides a default `appendLog()` implementation with trimming.
@MainActor
protocol Loggable: AnyObject {
    var log: [String] { get set }
}

extension Loggable {
    func appendLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        log.append(trimmed)
    }
}
