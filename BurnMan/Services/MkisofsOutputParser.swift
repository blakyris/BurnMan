import Foundation

// MARK: - Mkisofs Output Events

enum MkisofsEvent: Equatable {
    case progress(percent: Double)
    case extentsWritten(extents: Int, megabytes: Int)
    case error(String)
}

// MARK: - Mkisofs Output Parser

/// Parses mkisofs stderr/stdout output lines into structured events.
///
/// Confirmed output format:
/// ```
///  10.02% done, estimate finish Thu Jan  1 00:00:00 2025
/// Total translation table size: 0
/// 1234 extents written (2 MB)
/// ```
enum MkisofsOutputParser {

    // " 10.02% done, estimate finish..."
    nonisolated(unsafe) private static let progressRegex = #/\s*([\d.]+)%\s+done/#

    // "1234 extents written (2 MB)"
    nonisolated(unsafe) private static let extentsRegex = #/(\d+)\s+extents written\s+\((\d+)\s+MB\)/#

    static func parse(line: String) -> [MkisofsEvent] {
        var events: [MkisofsEvent] = []

        if let match = line.firstMatch(of: progressRegex),
           let pct = Double(match.1) {
            events.append(.progress(percent: pct))
        }

        if let match = line.firstMatch(of: extentsRegex),
           let extents = Int(match.1),
           let mb = Int(match.2) {
            events.append(.extentsWritten(extents: extents, megabytes: mb))
        }

        if line.contains("mkisofs:") && (line.contains("Error") || line.contains("error")) {
            events.append(.error(line))
        }

        return events
    }
}
