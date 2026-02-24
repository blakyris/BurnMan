import Foundation

// MARK: - Ffmpeg Progress Event

enum FfmpegEvent: Equatable {
    /// Current output time in seconds and encoding speed string (e.g. "2.5x").
    case progress(timeSeconds: Double, speed: String)
    /// ffmpeg signaled that encoding is complete.
    case completed
}

// MARK: - Ffmpeg Output Parser

/// Parses ffmpeg `-progress pipe:1` key=value lines into structured events.
enum FfmpegOutputParser {
    /// Parse a single key=value line. Returns nil for lines that aren't key=value pairs.
    static func parse(line: String) -> (key: String, value: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let eq = trimmed.firstIndex(of: "=") else { return nil }
        let key = String(trimmed[..<eq])
        let value = String(trimmed[trimmed.index(after: eq)...])
        return (key, value)
    }

    /// A stateful session that accumulates key=value pairs across lines
    /// and emits FfmpegEvent when enough context has been gathered.
    ///
    /// ffmpeg emits `out_time_us`, `speed`, and `progress` on separate lines.
    /// An event is only emitted on the `progress=continue` or `progress=end` line.
    class Session {
        private var lastTimeUs: Int64 = 0
        private var lastSpeed: String = ""

        /// Feed one line of ffmpeg progress output.
        /// Returns an event if one can be derived, nil otherwise.
        func feed(line: String) -> FfmpegEvent? {
            guard let (key, value) = FfmpegOutputParser.parse(line: line) else {
                return nil
            }

            switch key {
            case "out_time_us":
                if let us = Int64(value) { lastTimeUs = max(0, us) }
                return nil

            case "out_time_ms":
                // Some ffmpeg versions emit ms instead of us
                if let ms = Int64(value) { lastTimeUs = max(0, ms * 1000) }
                return nil

            case "speed":
                lastSpeed = value
                return nil

            case "progress":
                if value == "end" { return .completed }
                // "continue" — emit progress with accumulated values
                let seconds = Double(lastTimeUs) / 1_000_000.0
                return .progress(timeSeconds: seconds, speed: lastSpeed)

            default:
                return nil
            }
        }
    }
}
