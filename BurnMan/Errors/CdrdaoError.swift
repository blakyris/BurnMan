import Foundation

/// Errors produced by cdrdao.
enum CdrdaoError: ToolError {
    case deviceNotFound
    case noDisc
    case discNotEmpty
    case cannotReadDisc
    case writeError
    case bufferUnderrun
    case incompatibleMedium
    case tocNotFound
    case tocInvalid
    case blankFailed
    case scsiError
    case capacityExceeded
    case deviceSetupFailed
    case genericError(String)

    var toolName: String { "cdrdao" }

    var code: Int {
        switch self {
        case .deviceNotFound:      return 10
        case .noDisc:              return 11
        case .discNotEmpty:        return 12
        case .cannotReadDisc:      return 13
        case .writeError:          return 14
        case .bufferUnderrun:      return 15
        case .incompatibleMedium:  return 16
        case .tocNotFound:         return 17
        case .tocInvalid:          return 18
        case .blankFailed:         return 19
        case .scsiError:           return 20
        case .capacityExceeded:    return 21
        case .deviceSetupFailed:   return 22
        case .genericError:        return 1
        }
    }

    var errorDescription: String? {
        switch self {
        case .deviceNotFound:      return "Le graveur n'a pas été trouvé."
        case .noDisc:              return "Aucun disque dans le lecteur."
        case .discNotEmpty:        return "Le disque n'est pas vide."
        case .cannotReadDisc:      return "Impossible de lire le disque."
        case .writeError:          return "Erreur d'écriture."
        case .bufferUnderrun:      return "Buffer underrun — essayez une vitesse plus basse."
        case .incompatibleMedium:  return "Média incompatible avec ce graveur."
        case .tocNotFound:         return "Fichier TOC introuvable."
        case .tocInvalid:          return "Fichier TOC invalide."
        case .blankFailed:         return "Échec de l'effacement du disque."
        case .scsiError:           return "Erreur de communication SCSI."
        case .capacityExceeded:    return "La durée totale dépasse la capacité du disque."
        case .deviceSetupFailed:   return "Impossible d'initialiser le graveur. Débranchez et rebranchez le lecteur."
        case .genericError(let msg): return msg
        }
    }

    // MARK: - Factory

    private static let patterns: [(pattern: String, error: CdrdaoError)] = [
        ("Cannot open SCSI",        .deviceNotFound),
        ("No disk in drive",        .noDisc),
        ("Medium not present",      .noDisc),
        ("Disk is not empty",       .discNotEmpty),
        ("Cannot determine disk",   .cannotReadDisc),
        ("Write data failed",       .writeError),
        ("Write error",             .writeError),
        ("Buffer under run",        .bufferUnderrun),
        ("Incompatible medium",     .incompatibleMedium),
        ("Cannot open.*toc",        .tocNotFound),
        ("Illegal toc",             .tocInvalid),
        ("Illegal cue",             .tocInvalid),
        ("Syntax error",            .tocInvalid),
        ("Blanking failed",         .blankFailed),
        ("SCSI command failed",     .scsiError),
        ("exceeds",                 .capacityExceeded),
        ("Cannot setup device",     .deviceSetupFailed),
        ("giving up",               .deviceSetupFailed),
    ]

    static func from(exitCode: Int32, stderr: String) -> CdrdaoError {
        let lower = stderr.lowercased()
        for (pattern, error) in patterns {
            if lower.contains(pattern.lowercased()) {
                return error
            }
        }
        return .genericError("Erreur cdrdao (code \(exitCode))")
    }
}
