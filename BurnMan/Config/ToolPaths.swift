import Foundation

/// Centralized resolution of all bundled CLI tool paths.
/// Every tool lives in `BurnMan.app/Contents/Frameworks/`.
enum ToolPaths {
    // CD burning (cdrdao for raw DAO mode)
    static var cdrdao: String { bundledPath(for: "cdrdao") }

    // DVD/BD booktype
    static var dvdRwBooktype: String { bundledPath(for: "dvd+rw-booktype") }

    // ISO mastering (mkisofs from cdrtools)
    static var mkisofs: String { bundledPath(for: "mkisofs") }

    // ISO manipulation (xorriso — future: addToISO, removeFromISO, listISO)
    static var xorriso: String { bundledPath(for: "xorriso") }

    // DVD-Audio authoring
    static var dvdaAuthor: String { bundledPath(for: "dvda-author") }

    // Media tools
    static var ffmpeg: String { bundledPath(for: "ffmpeg") }
    static var ffprobe: String { bundledPath(for: "ffprobe") }

    // System tools (not bundled)
    static var dd: String { "/bin/dd" }

    /// All tool names accepted by the privileged helper (bundled tools).
    static let allowedToolNames: Set<String> = [
        "cdrdao", "xorriso", "dvd+rw-booktype",
    ]

    /// System tool paths accepted by the privileged helper.
    static let allowedSystemToolPaths: Set<String> = [
        "/bin/dd",
    ]

    /// The Frameworks directory inside the app bundle.
    /// Returns nil in unit test or non-standard bundle environments.
    static var frameworksDirectory: String? {
        Bundle.main.privateFrameworksPath
    }

    private static func bundledPath(for name: String) -> String {
        guard let dir = frameworksDirectory else { return name }
        return (dir as NSString).appendingPathComponent(name)
    }
}
