import Foundation

/// Errors produced by growisofs.
enum GrowisofsError: ToolError {
    case noMedia
    case mediaNotBlank
    case notAppendable
    case unsupportedMedia
    case deviceError
    case writeFailed
    case noFreeSpace
    case signaled(Int)
    case genericError(String)

    var toolName: String { "growisofs" }

    var code: Int {
        switch self {
        case .noMedia:          return 10
        case .mediaNotBlank:    return 11
        case .notAppendable:    return 12
        case .unsupportedMedia: return 13
        case .deviceError:      return 14
        case .writeFailed:      return 15
        case .noFreeSpace:      return 16
        case .signaled(let s):  return 128 + s
        case .genericError:     return 1
        }
    }

    var errorDescription: String? {
        switch self {
        case .noMedia:          return "Aucun média dans le lecteur."
        case .mediaNotBlank:    return "Le média n'est pas vide."
        case .notAppendable:    return "Le média n'est pas appendable."
        case .unsupportedMedia: return "Type de média non supporté."
        case .deviceError:      return "Impossible d'ouvrir le graveur."
        case .writeFailed:      return "Erreur d'écriture."
        case .noFreeSpace:      return "Pas assez d'espace sur le média."
        case .signaled(let s):  return "Processus interrompu par signal \(s)."
        case .genericError(let msg): return msg
        }
    }

    // MARK: - Factory

    private static let patterns: [(pattern: String, error: GrowisofsError)] = [
        ("no media present",        .noMedia),
        ("media is not blank",      .mediaNotBlank),
        ("media is not appendable", .notAppendable),
        ("unsupported media",       .unsupportedMedia),
        ("unable to open",          .deviceError),
        ("write failed",            .writeFailed),
        ("no free space",           .noFreeSpace),
    ]

    static func from(exitCode: Int32, stderr: String) -> GrowisofsError {
        let lower = stderr.lowercased()
        for (pattern, error) in patterns {
            if lower.contains(pattern) {
                return error
            }
        }
        if exitCode >= 128 {
            return .signaled(Int(exitCode) - 128)
        }
        return .genericError("Erreur growisofs (code \(exitCode))")
    }
}
