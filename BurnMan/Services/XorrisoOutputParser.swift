import Foundation

// MARK: - Xorriso Output Events

/// Events emitted by the xorriso output parser.
enum XorrisoEvent: Equatable {
    case progressUpdated(currentMB: Int, totalMB: Int)
    case bufferFill(fifo: Int, drive: Int)
    case writeSpeed(String)
    case beginningTrack
    case writingFinished
    case error(String)
    case warning(String)
}

// MARK: - Xorriso Output Parser

/// Parses xorriso stderr/stdout output lines into structured events.
///
/// Confirmed output format (mode `-as cdrecord -v`):
/// ```
/// Beginning to write data track.
/// xorriso : UPDATE :    3 of  200 MB written (fifo  0%) [buf  50%]
/// xorriso : UPDATE :  103 of  200 MB written (fifo  0%) [buf  50%]  66.7x.
/// Writing to '...' completed successfully.
/// ```
enum XorrisoOutputParser {

    // MARK: - Precompiled Patterns

    // "  103 of  200 MB written (fifo  0%) [buf  50%]  66.7x."
    nonisolated(unsafe) private static let progressRegex: Regex<(Substring, Substring, Substring, Substring, Substring, Substring?)> = #/(\d+)\s+of\s+(\d+)\s+MB written \(fifo\s+(\d+)%\) \[buf\s+(\d+)%\](?:\s+([\d.]+)x)?/#

    // MARK: - Parse

    /// Parse a single line of xorriso output and return all detected events.
    static func parse(line: String) -> [XorrisoEvent] {
        var events: [XorrisoEvent] = []

        // 1. Progress: "xorriso : UPDATE :  103 of  200 MB written (fifo  0%) [buf  50%]  66.7x."
        if let match = line.firstMatch(of: progressRegex),
           let cur = Int(match.1),
           let tot = Int(match.2),
           let fifo = Int(match.3),
           let drive = Int(match.4) {
            events.append(.progressUpdated(currentMB: cur, totalMB: tot))
            events.append(.bufferFill(fifo: fifo, drive: drive))
            if let speedStr = match.5 {
                events.append(.writeSpeed(String(speedStr) + "x"))
            }
        }

        // 2. Beginning track
        if line.contains("Beginning to write") {
            events.append(.beginningTrack)
        }

        // 3. Writing finished
        if line.contains("completed successfully") {
            events.append(.writingFinished)
        }

        // 4. Failures
        if line.contains("FAILURE :") {
            let msg = extractMessage(from: line, after: "FAILURE :")
            events.append(.error(msg))
        }

        // 5. Warnings
        if line.contains("WARNING :") {
            let msg = extractMessage(from: line, after: "WARNING :")
            events.append(.warning(msg))
        }

        return events
    }

    /// Convenience method to apply parsed events via closures (same pattern as CdrdaoOutputParser).
    static func applyEvents(
        from line: String,
        onProgress: (Int, Int) -> Void,
        onBuffer: (Int, Int) -> Void,
        onSpeed: (String) -> Void,
        onFinished: () -> Void,
        onWarning: (String) -> Void
    ) {
        for event in parse(line: line) {
            switch event {
            case .progressUpdated(let cur, let tot):
                onProgress(cur, tot)
            case .bufferFill(let fifo, let drive):
                onBuffer(fifo, drive)
            case .writeSpeed(let speed):
                onSpeed(speed)
            case .writingFinished:
                onFinished()
            case .warning(let msg):
                onWarning(msg)
            case .beginningTrack, .error:
                break
            }
        }
    }

    // MARK: - Private

    private static func extractMessage(from line: String, after marker: String) -> String {
        guard let range = line.range(of: marker) else { return line }
        return String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
}
