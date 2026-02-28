import Foundation

/// Result of a full audio file probe (tags + stream info).
struct AudioFileProbeResult: Sendable {
    var duration: Double
    var sampleRate: Double
    var bitDepth: Int
    var channels: Int
    var tags: [String: String]  // keys UPPERCASED
}

/// Stateless wrapper around ffprobe. Read-only media analysis.
/// Executes via ToolRunner (non-root).
class MediaProbeService: @unchecked Sendable {

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
        let result = await ToolRunner().collect(
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

        let result = await ToolRunner().collect(
            executablePath: ToolPaths.ffprobe,
            arguments: args
        )

        guard result.exitCode == 0 else { return nil }
        return result.data
    }

    // MARK: - Audio CD Probing

    /// Full audio file probe returning tags + stream info.
    func probeAudioFile(url: URL) async -> AudioFileProbeResult? {
        let runner = ToolRunner()
        let result = await runner.collect(
            executablePath: ToolPaths.ffprobe,
            arguments: ["-v", "error", "-print_format", "json",
                        "-show_format", "-show_streams",
                        url.path(percentEncoded: false)]
        )

        guard result.exitCode == 0,
              let output = try? JSONDecoder().decode(FfprobeOutput.self, from: result.data)
        else { return nil }

        let format = output.format
        let audio = (output.streams ?? []).first(where: { $0.isAudio })

        let rawTags = format?.tags ?? [:]
        let uppercasedTags = Dictionary(uniqueKeysWithValues: rawTags.map { ($0.key.uppercased(), $0.value) })

        return AudioFileProbeResult(
            duration: format?.durationSeconds ?? 0,
            sampleRate: audio?.sampleRateHz ?? 0,
            bitDepth: audio?.effectiveBitDepth ?? 0,
            channels: audio?.channels ?? 0,
            tags: uppercasedTags
        )
    }

    /// Lightweight WAV bit depth probe.
    func probeBitDepth(url: URL) async -> Int {
        let runner = ToolRunner()
        let result = await runner.collect(
            executablePath: ToolPaths.ffprobe,
            arguments: ["-v", "error", "-select_streams", "a:0",
                        "-show_entries", "stream=bits_per_raw_sample,bits_per_sample",
                        "-of", "csv=p=0",
                        url.path(percentEncoded: false)]
        )
        guard result.exitCode == 0 else { return 0 }
        let output = String(data: result.data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let values = output.split(separator: ",")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        return values.first(where: { $0 > 0 }) ?? 0
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

        let result = await ToolRunner().collect(
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
