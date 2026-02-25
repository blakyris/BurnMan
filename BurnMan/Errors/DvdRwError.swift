import Foundation

/// Errors produced by dvd+rw-format and dvd+rw-mediainfo.
enum DvdRwError: ToolError {
    case notDVD
    case alreadyFormatted
    case formatFailed
    case cannotProceed
    case genericError(String)

    var toolName: String { "dvd+rw-format" }

    var code: Int {
        switch self {
        case .notDVD:           return 10
        case .alreadyFormatted: return 11
        case .formatFailed:     return 12
        case .cannotProceed:    return 13
        case .genericError:     return 1
        }
    }

    var errorDescription: String? {
        switch self {
        case .notDVD:           return "Le média n'est pas un DVD."
        case .alreadyFormatted: return "Le média est déjà formaté."
        case .formatFailed:     return "Échec du formatage."
        case .cannotProceed:    return "Impossible de continuer."
        case .genericError(let msg): return msg
        }
    }

    // MARK: - Factory

    private static let patterns: [(pattern: String, error: DvdRwError)] = [
        ("not a dvd",          .notDVD),
        ("already formatted",  .alreadyFormatted),
        ("format failed",      .formatFailed),
        ("unable to proceed",  .cannotProceed),
    ]

    static func from(exitCode: Int32, stderr: String) -> DvdRwError {
        let lower = stderr.lowercased()
        for (pattern, error) in patterns {
            if lower.contains(pattern) {
                return error
            }
        }
        return .genericError("Erreur dvd+rw-format (code \(exitCode))")
    }
}
