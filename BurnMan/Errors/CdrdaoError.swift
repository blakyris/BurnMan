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
        case .deviceNotFound:      return "Drive not found."
        case .noDisc:              return "No disc in the drive."
        case .discNotEmpty:        return "Disc is not empty."
        case .cannotReadDisc:      return "Unable to read disc."
        case .writeError:          return "Write error."
        case .bufferUnderrun:      return "Buffer underrun — try a lower speed."
        case .incompatibleMedium:  return "Incompatible media for this drive."
        case .tocNotFound:         return "TOC file not found."
        case .tocInvalid:          return "Invalid TOC file."
        case .blankFailed:         return "Disc erase failed."
        case .scsiError:           return "SCSI communication error."
        case .capacityExceeded:    return "Total duration exceeds disc capacity."
        case .deviceSetupFailed:   return "Unable to initialize drive. Unplug and reconnect the drive."
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
        return .genericError("cdrdao error (code \(exitCode))")
    }
}
