import Foundation

/// Centralized resolution of all bundled CLI tool paths.
/// Every tool lives in `BurnMan.app/Contents/Frameworks/`.
enum ToolPaths {
    // CD burning
    static var cdrdao: String { bundledPath(for: "cdrdao") }

    // DVD/BD burning
    static var growisofs: String { bundledPath(for: "growisofs") }
    static var dvdRwFormat: String { bundledPath(for: "dvd+rw-format") }
    static var dvdRwMediainfo: String { bundledPath(for: "dvd+rw-mediainfo") }
    static var dvdRwBooktype: String { bundledPath(for: "dvd+rw-booktype") }

    // Media tools
    static var ffmpeg: String { bundledPath(for: "ffmpeg") }
    static var ffprobe: String { bundledPath(for: "ffprobe") }
    static var ffplay: String { bundledPath(for: "ffplay") }

    // System tools (not bundled)
    static var dd: String { "/bin/dd" }

    /// All tool names accepted by the privileged helper (bundled tools).
    static let allowedToolNames: Set<String> = [
        "cdrdao", "growisofs", "dvd+rw-format", "dvd+rw-mediainfo", "dvd+rw-booktype",
    ]

    /// System tool paths accepted by the privileged helper.
    static let allowedSystemToolPaths: Set<String> = [
        "/bin/dd",
    ]

    /// The Frameworks directory inside the app bundle.
    static var frameworksDirectory: String {
        guard let path = Bundle.main.privateFrameworksPath else {
            fatalError("Bundle Frameworks directory not found")
        }
        return path
    }

    private static func bundledPath(for name: String) -> String {
        (frameworksDirectory as NSString).appendingPathComponent(name)
    }
}
