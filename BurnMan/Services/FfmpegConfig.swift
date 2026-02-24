import Foundation

enum FfmpegConfig {
    static var resolvedPath: String { bundledPath(for: "ffmpeg") }
    static var ffprobePath: String { bundledPath(for: "ffprobe") }
    static var ffplayPath: String { bundledPath(for: "ffplay") }

    private static func bundledPath(for name: String) -> String {
        guard let frameworksPath = Bundle.main.privateFrameworksPath else {
            fatalError("\(name) non trouvé dans le bundle")
        }
        return (frameworksPath as NSString).appendingPathComponent(name)
    }
}
