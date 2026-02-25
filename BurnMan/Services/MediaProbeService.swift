import Foundation

/// Stateless wrapper around ffprobe. Read-only media analysis.
/// Executes via ToolRunner (non-root).
class MediaProbeService: @unchecked Sendable {
    private let toolRunner: ToolRunner

    init(toolRunner: ToolRunner) {
        self.toolRunner = toolRunner
    }

    // MARK: - Full Analysis

    /// Probes a media file and returns structured info.
    func probe(url: URL) async throws -> MediaInfo {
        let output = try await runProbe(url: url)
        return MediaInfo.from(url: url, output: output)
    }

    // MARK: - Convenience

    /// Returns the duration in seconds.
    func duration(url: URL) async throws -> Double {
        let output = try await runProbe(url: url)
        return output.format?.durationSeconds ?? 0
    }

    /// Returns audio stream info.
    func audioStreams(url: URL) async throws -> [FfprobeStream] {
        let output = try await runProbe(url: url)
        return (output.streams ?? []).filter { $0.isAudio }
    }

    /// Returns video stream info.
    func videoStreams(url: URL) async throws -> [FfprobeStream] {
        let output = try await runProbe(url: url)
        return (output.streams ?? []).filter { $0.isVideo }
    }

    /// Extracts embedded artwork (cover art) data.
    func artwork(url: URL) async -> Data? {
        let args = [
            "-v", "quiet",
            "-i", url.path,
            "-an", "-vcodec", "copy",
            "-f", "image2pipe", "-",
        ]
        let result = await toolRunner.collect(
            executablePath: ToolPaths.ffmpeg,
            arguments: args
        )
        guard result.exitCode == 0, !result.data.isEmpty else { return nil }
        return result.data
    }

    /// Returns chapter markers.
    func chapters(url: URL) async throws -> [FfprobeChapter] {
        let output = try await runProbe(url: url)
        return output.chapters ?? []
    }

    /// Probes a DVD title and returns raw JSON data, or nil if the title doesn't exist.
    func probeDVDTitle(devicePath: String, titleNumber: Int) async -> Data? {
        let args = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            "-show_chapters",
            "-f", "dvdvideo",
            "-title", "\(titleNumber)",
            "-i", devicePath,
        ]

        let result = await toolRunner.collect(
            executablePath: ToolPaths.ffprobe,
            arguments: args
        )

        guard result.exitCode == 0 else { return nil }
        return result.data
    }

    // MARK: - Private

    private func runProbe(url: URL) async throws -> FfprobeOutput {
        let args = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            "-show_chapters",
            url.path,
        ]

        let result = await toolRunner.collect(
            executablePath: ToolPaths.ffprobe,
            arguments: args
        )

        guard result.exitCode == 0 else {
            throw FfmpegError.from(
                exitCode: result.exitCode,
                stderr: String(data: result.data, encoding: .utf8) ?? ""
            )
        }

        do {
            return try JSONDecoder().decode(FfprobeOutput.self, from: result.data)
        } catch {
            throw FfmpegError.invalidData
        }
    }
}
