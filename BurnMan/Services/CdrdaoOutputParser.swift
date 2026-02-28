import Foundation

// MARK: - Cdrdao Output Events

/// Events emitted by the cdrdao output parser.
enum CdrdaoEvent: Equatable {
    case phaseChanged(BurnPhase)
    case progressUpdated(currentMB: Int, totalMB: Int)
    case bufferFill(fifo: Int, drive: Int)
    case trackChanged(Int)
    case startingWrite(speed: String, simulation: Bool)
    case pausing
    case blanking
    case writingFinished
    case warning(String)
    case error(String)
}

// MARK: - Cdrdao Output Parser

/// Parses cdrdao stderr output lines into structured events.
/// All regex patterns are compiled once as static constants.
enum CdrdaoOutputParser {

    // MARK: - User-Facing Message Mappings

    private static let errorMappings: [(pattern: String, message: String)] = [
        ("Cannot open disk",             "File not found or inaccessible."),
        ("Cannot open",                  "Unable to open file."),
        ("Cannot determine length",      "Corrupted audio file or invalid format."),
        ("Unit not ready",               "Drive not ready (check that a disc is inserted)."),
        ("Medium not present",           "No disc in the drive."),
        ("Write data failed",            "Write failed — the disc may be defective or speed too high."),
        ("Cannot open SCSI",             "Drive not found or in use by another application."),
        ("Illegal cue sheet",            "Malformed TOC/CUE file."),
        ("Power calibration",            "Defective disc calibration area — try another disc."),
        ("Medium write protected",       "Disc is write-protected (already burned)."),
        ("Incompatible medium",          "Incompatible disc for this drive."),
        ("Could not read disk",          "Source disc read error."),
        ("Invalid track mode",           "Incompatible track mode."),
        ("Blanking failed",              "Disc erase failed."),
        ("exceeds",                      "Total duration exceeds disc capacity. Reduce the number of tracks or enable Overburn."),
        ("Cannot setup device",          "Unable to initialize drive. Unplug and reconnect the drive, or restart."),
        ("giving up",                    "Drive not responding. Unplug and reconnect the drive."),
    ]

    private static let warningMappings: [(pattern: String, message: String)] = [
        ("seems to be written",          "This disc appears to already be burned."),
        ("Speed value not supported",    "Burn speed not supported by the drive."),
    ]

    private static func humanReadableMessage(
        from rawLine: String,
        mappings: [(pattern: String, message: String)],
        fallback: String
    ) -> String {
        for (pattern, message) in mappings {
            if rawLine.localizedCaseInsensitiveContains(pattern) {
                return message
            }
        }
        return fallback
    }

    // MARK: - Precompiled Patterns

    nonisolated(unsafe) private static let wroteProgressRegex = /Wrote\s+(\d+)\s+of\s+(\d+)\s+MB/
    nonisolated(unsafe) private static let bufferFillRegex = /Buffers\s+(\d+)%\s+(\d+)%/
    nonisolated(unsafe) private static let writingTrackRegex = /Writing track\s+(\d+)/
    nonisolated(unsafe) private static let startingWriteRegex = /Starting write\s+(simulation\s+)?at speed\s+(\d+)/
    nonisolated(unsafe) private static let pausingRegex = /(?i)Pausing\s+\d+\s+seconds/
    nonisolated(unsafe) private static let warningRegex = /^WARNING:\s*(.+)/

    // MARK: - Parse

    /// Parses a cdrdao output line and applies events via closures.
    /// This avoids duplicating the switch logic across managers.
    static func applyEvents(
        from line: String,
        onPhase: (BurnPhase) -> Void,
        onProgress: (Int, Int) -> Void,
        onBuffer: (Int, Int) -> Void,
        onTrack: (Int) -> Void,
        onStartingWrite: (String, Bool) -> Void,
        onWarning: (String) -> Void
    ) {
        for event in parse(line: line) {
            switch event {
            case .phaseChanged(let phase):
                onPhase(phase)
            case .progressUpdated(let cur, let tot):
                onProgress(cur, tot)
            case .bufferFill(let fifo, let drive):
                onBuffer(fifo, drive)
            case .trackChanged(let n):
                onTrack(n)
            case .startingWrite(let speed, let sim):
                onStartingWrite(speed, sim)
            case .warning(let msg):
                onWarning(msg)
            case .pausing, .blanking, .writingFinished, .error:
                break
            }
        }
    }

    // MARK: - Exit Code Description

    /// Translates a cdrdao/helper exit code into a user-facing message.
    static func describeExitCode(_ code: Int32, helperMessage: String) -> String {
        if !helperMessage.isEmpty { return helperMessage }
        switch code {
        case 0: return "Success"
        case 1: return "General cdrdao error"
        case 2: return "cdrdao usage error"
        case -1: return "Invalid cdrdao path"
        case -2: return "Invalid arguments"
        case -3: return "Invalid working directory"
        case -4: return "Invalid log path"
        case -5: return "Unable to launch cdrdao"
        default:
            if code > 128 {
                let signal = code - 128
                if signal == 15 { return "cdrdao interrupted (cancelled)" }
                return "cdrdao killed by signal \(signal)"
            }
            return "cdrdao code \(code)"
        }
    }

    /// Parse a single line of cdrdao output and return all detected events.
    /// A single line may produce multiple events (e.g. progress + buffer fill).
    static func parse(line: String) -> [CdrdaoEvent] {
        var events: [CdrdaoEvent] = []

        // 1. Track: "Writing track 01 (mode AUDIO/AUDIO )..."
        if let match = line.firstMatch(of: writingTrackRegex),
           let trackNum = Int(match.1) {
            events.append(.trackChanged(trackNum))
            events.append(.phaseChanged(.writingTrack(trackNum)))
        }

        // 2. Progress: "Wrote 1 of 556 MB (Buffers 100% 97%)."
        if let match = line.firstMatch(of: wroteProgressRegex),
           let cur = Int(match.1),
           let tot = Int(match.2) {
            events.append(.progressUpdated(currentMB: cur, totalMB: tot))
        }

        // 3. Buffer fill: "Buffers 100% 97%"
        if let match = line.firstMatch(of: bufferFillRegex),
           let fifo = Int(match.1),
           let drive = Int(match.2) {
            events.append(.bufferFill(fifo: fifo, drive: drive))
        }

        // 4. Starting write: "Starting write at speed 24..."
        //    or simulation:  "Starting write simulation at speed 8..."
        if let match = line.firstMatch(of: startingWriteRegex) {
            let isSimulation = match.1 != nil
            let speed = String(match.2) + "x"
            events.append(.startingWrite(speed: speed, simulation: isSimulation))
            events.append(.phaseChanged(.starting))
        }

        // 5. Pausing: "Pausing 10 seconds - hit CTRL-C to abort."
        if line.firstMatch(of: pausingRegex) != nil {
            events.append(.pausing)
            events.append(.phaseChanged(.pausing))
        }

        // 6. Blanking: "Blanking entire disc..." / "Blanking minimal..."
        if line.contains("Blanking") {
            events.append(.blanking)
            events.append(.phaseChanged(.blanking))
        }

        // 7. Calibration: "Power calibration area..."
        if line.contains("Power calibration") || line.contains("calibration area") {
            events.append(.phaseChanged(.calibrating))
        }

        // 8. Lead-in
        if line.contains("Writing lead-in") {
            events.append(.phaseChanged(.writingLeadIn))
        }

        // 9. Lead-out
        if line.contains("Writing lead-out") {
            events.append(.phaseChanged(.writingLeadOut))
        }

        // 10. Flushing
        if line.contains("Flushing") {
            events.append(.phaseChanged(.flushing))
        }

        // 11. Writing finished successfully
        if line.contains("Writing finished successfully") {
            events.append(.writingFinished)
        }

        // 12. Warnings — only show warnings that match known mappings
        if let match = line.firstMatch(of: warningRegex) {
            let rawWarning = String(match.1)
            for (pattern, message) in warningMappings {
                if rawWarning.localizedCaseInsensitiveContains(pattern) {
                    events.append(.warning(message))
                    break
                }
            }
        }

        // 13. Errors
        if line.contains("ERROR:") || line.contains("Write data failed") {
            let friendlyError = humanReadableMessage(
                from: line,
                mappings: errorMappings,
                fallback: "cdrdao error: \(line)"
            )
            events.append(.error(line))
            events.append(.phaseChanged(.failed(friendlyError)))
        }

        return events
    }
}
