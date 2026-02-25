import Foundation

/// Detects the availability of disc decryption libraries at runtime.
///
/// Probes for `libdvdcss.2.dylib` via `dlopen`, checking the app bundle
/// first (bundled with ffmpeg), then system locations as fallback.
///
/// libdvdcss is loaded automatically by libdvdread (linked into our ffmpeg),
/// so this service only needs to:
/// 1. Detect whether libdvdcss is available (for UI feedback)
/// 2. Provide environment variables when launching ffmpeg for DVD reading
class DecryptionService: @unchecked Sendable {

    // MARK: - Search Paths

    private static let dvdCssSearchPaths = [
        (ToolPaths.frameworksDirectory as NSString)
            .appendingPathComponent("libdvdcss.2.dylib"),
        "/usr/local/lib/libdvdcss.2.dylib",
        "/opt/homebrew/lib/libdvdcss.2.dylib",
        "/usr/lib/libdvdcss.2.dylib",
    ]

    // MARK: - State

    /// Whether libdvdcss was found on the system.
    let isDvdCssAvailable: Bool

    /// The path where libdvdcss was found, if any.
    let dvdCssPath: String?

    // MARK: - Init

    init() {
        var foundPath: String?

        for path in Self.dvdCssSearchPaths {
            if let handle = dlopen(path, RTLD_LAZY) {
                dlclose(handle)
                foundPath = path
                break
            }
        }

        self.dvdCssPath = foundPath
        self.isDvdCssAvailable = foundPath != nil
    }

    // MARK: - Environment

    /// Returns environment variables to set when launching ffmpeg/libdvdread
    /// so that libdvdcss is found and used for CSS decryption.
    var dvdEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment

        if let path = dvdCssPath {
            // Ensure DYLD_LIBRARY_PATH includes the directory containing libdvdcss
            let dir = (path as NSString).deletingLastPathComponent
            if let existing = env["DYLD_LIBRARY_PATH"] {
                env["DYLD_LIBRARY_PATH"] = "\(dir):\(existing)"
            } else {
                env["DYLD_LIBRARY_PATH"] = dir
            }
        }

        return env
    }
}
