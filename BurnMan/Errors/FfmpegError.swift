import Foundation

/// Errors produced by ffmpeg.
enum FfmpegError: ToolError {
    case fileNotFound
    case invalidData
    case codecNotFound
    case outputExists
    case permissionDenied
    case unsupportedFormat
    case genericError(String)

    var toolName: String { "ffmpeg" }

    var code: Int {
        switch self {
        case .fileNotFound:      return 10
        case .invalidData:       return 11
        case .codecNotFound:     return 12
        case .outputExists:      return 13
        case .permissionDenied:  return 14
        case .unsupportedFormat: return 15
        case .genericError:      return 1
        }
    }

    var errorDescription: String? {
        switch self {
        case .fileNotFound:      return "File not found."
        case .invalidData:       return "Invalid data."
        case .codecNotFound:     return "Codec not found."
        case .outputExists:      return "Output file already exists."
        case .permissionDenied:  return "Permission denied."
        case .unsupportedFormat: return "Unsupported format."
        case .genericError(let msg): return msg
        }
    }

    // MARK: - Factory

    private static let patterns: [(pattern: String, error: FfmpegError)] = [
        ("no such file or directory", .fileNotFound),
        ("invalid data found",        .invalidData),
        ("unknown encoder",           .codecNotFound),
        ("unknown decoder",           .codecNotFound),
        ("already exists",            .outputExists),
        ("permission denied",         .permissionDenied),
        ("not supported",             .unsupportedFormat),
    ]

    static func from(exitCode: Int32, stderr: String) -> FfmpegError {
        let lower = stderr.lowercased()
        for (pattern, error) in patterns {
            if lower.contains(pattern) {
                return error
            }
        }
        return .genericError("ffmpeg error (code \(exitCode))")
    }
}
