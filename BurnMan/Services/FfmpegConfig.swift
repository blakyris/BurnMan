import Foundation

enum FfmpegConfig {
    static var resolvedPath: String { ToolPaths.ffmpeg }
    static var ffprobePath: String { ToolPaths.ffprobe }
    static var ffplayPath: String { ToolPaths.ffplay }
}
