import Foundation

/// Centralized construction of log file paths used for helper IPC.
/// The privileged helper validates that log paths start with `/tmp/`,
/// so these must use `/tmp/` (not `FileManager.default.temporaryDirectory`).
enum HelperLogPath {
    private static let pid = ProcessInfo.processInfo.processIdentifier

    static var audioBurn: String { "/tmp/cdrburn_audio_\(pid).log" }
    static var discCopy: String { "/tmp/burnman_copy_\(pid).log" }
    static var discImage: String { "/tmp/burnman_image_\(pid).log" }
    static var imageBurn: String { "/tmp/cdrburn_\(pid).log" }
    static var unlock: String { "/tmp/cdrburn_unlock.log" }
}
