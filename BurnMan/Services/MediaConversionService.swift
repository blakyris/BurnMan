import Foundation

/// Video standard for DVD encoding.
enum VideoStandard: String, CaseIterable, Identifiable {
    case ntsc
    case pal

    var id: String { rawValue }

    var resolution: (width: Int, height: Int) {
        switch self {
        case .ntsc: return (720, 480)
        case .pal:  return (720, 576)
        }
    }

    var frameRate: String {
        switch self {
        case .ntsc: return "29.97"
        case .pal:  return "25"
        }
    }
}

/// Blu-ray target resolution.
enum BlurayResolution: String, CaseIterable, Identifiable {
    case fullHD = "1920x1080"
    case hd = "1280x720"

    var id: String { rawValue }

    var width: Int {
        switch self {
        case .fullHD: return 1920
        case .hd:     return 1280
        }
    }

    var height: Int {
        switch self {
        case .fullHD: return 1080
        case .hd:     return 720
        }
    }
}

/// Stateless wrapper around ffmpeg for conversion, encoding, and tag writing.
/// Executes via ToolRunner (non-root).
class MediaConversionService: @unchecked Sendable {
    private let toolRunner: ToolRunner

    init(toolRunner: ToolRunner) {
        self.toolRunner = toolRunner
    }

    func cancel() {
        Task { @MainActor in
            toolRunner.cancel()
        }
    }

    // MARK: - Audio Conversion

    /// Converts to CD-quality WAV (16-bit, 44.1kHz, stereo).
    func convertToCDWav(
        input: URL,
        output: URL,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-ar", "44100", "-ac", "2", "-sample_fmt", "s16",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Converts to MP3.
    func convertToMP3(
        input: URL,
        output: URL,
        bitrate: Int = 320,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:a", "libmp3lame", "-b:a", "\(bitrate)k",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Converts to FLAC.
    func convertToFLAC(
        input: URL,
        output: URL,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:a", "flac",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Converts to AAC.
    func convertToAAC(
        input: URL,
        output: URL,
        bitrate: Int = 256,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:a", "aac", "-b:a", "\(bitrate)k",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Converts to AC-3 (for DVD/BD audio).
    func convertToAC3(
        input: URL,
        output: URL,
        channels: Int = 6,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:a", "ac3", "-ac", "\(channels)",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Converts to DTS.
    func convertToDTS(
        input: URL,
        output: URL,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:a", "dca",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    // MARK: - Video Encoding

    /// Encodes to MPEG-2 DVD format.
    func encodeDVD(
        input: URL,
        output: URL,
        standard: VideoStandard = .ntsc,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let res = standard.resolution
        let args = [
            "-i", input.path,
            "-target", "\(standard.rawValue)-dvd",
            "-vf", "scale=\(res.width):\(res.height)",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Encodes to H.264 Blu-ray format.
    func encodeBluray(
        input: URL,
        output: URL,
        resolution: BlurayResolution = .fullHD,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:v", "libx264", "-preset", "medium",
            "-codec:a", "ac3",
            "-vf", "scale=\(resolution.width):\(resolution.height)",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    /// Creates a streamable fragmented MP4 for AVPlayer preview.
    func streamToMP4(
        input: URL,
        output: URL,
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        let args = [
            "-i", input.path,
            "-codec:v", "libx264", "-preset", "ultrafast",
            "-codec:a", "aac",
            "-movflags", "+frag_keyframe+empty_moov+faststart",
            "-y", output.path,
        ]
        let duration = await fileDuration(input)
        return await runFfmpeg(args: args, totalDuration: duration, progress: progress)
    }

    // MARK: - DVD Extraction

    /// Extracts a DVD title using ffmpeg's dvdvideo demuxer.
    /// Requires ffmpeg compiled with `--enable-libdvdnav --enable-libdvdread`.
    /// libdvdcss is loaded automatically by libdvdread for CSS-encrypted discs.
    func extractDVDTitle(
        devicePath: String,
        titleNumber: Int,
        output: URL,
        codec: String = "copy",
        progress: (@MainActor (Double) -> Void)? = nil
    ) async -> Int32 {
        var args = [
            "-f", "dvdvideo",
            "-title", "\(titleNumber)",
            "-i", devicePath,
        ]
        if codec == "copy" {
            args += ["-codec", "copy"]
        } else {
            args += ["-codec:v", "libx264", "-preset", "medium", "-codec:a", "aac"]
        }
        args += ["-y", output.path]

        return await runFfmpeg(args: args, totalDuration: nil, progress: progress)
    }

    // MARK: - Metadata

    /// Writes tags (ID3/Vorbis/MP4) to a media file.
    func writeTags(url: URL, tags: [String: String]) async -> Int32 {
        var args = ["-i", url.path]
        for (key, value) in tags {
            args += ["-metadata", "\(key)=\(value)"]
        }
        args += ["-codec", "copy", "-y", url.path]
        return await runFfmpeg(args: args, totalDuration: nil, progress: nil)
    }

    // MARK: - DRY Helper

    /// Shared helper for all ffmpeg invocations.
    /// Manages progress parsing and reporting via `FfmpegOutputParser.Session`.
    private func runFfmpeg(
        args: [String],
        totalDuration: Double?,
        progress: (@MainActor (Double) -> Void)?
    ) async -> Int32 {
        // Add progress flags for parseable output
        var fullArgs = ["-progress", "pipe:1", "-nostats"]
        fullArgs += args

        let session = FfmpegOutputParser.Session()

        let exitCode = await toolRunner.run(
            executablePath: ToolPaths.ffmpeg,
            arguments: fullArgs
        ) { @MainActor line in
            guard let event = session.feed(line: line) else { return }
            switch event {
            case .progress(let timeSeconds, _):
                if let total = totalDuration, total > 0 {
                    let pct = min(timeSeconds / total, 1.0)
                    progress?(pct)
                }
            case .completed:
                progress?(1.0)
            }
        }

        return exitCode
    }

    /// Gets the duration of a media file via ffprobe (quick).
    private func fileDuration(_ url: URL) async -> Double? {
        let args = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            url.path,
        ]
        let result = await toolRunner.collect(
            executablePath: ToolPaths.ffprobe,
            arguments: args
        )
        guard result.exitCode == 0,
              let output = try? JSONDecoder().decode(FfprobeOutput.self, from: result.data) else {
            return nil
        }
        return output.format?.durationSeconds
    }
}
