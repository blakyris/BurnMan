import Foundation

// MARK: - Codable ffprobe output models

/// Top-level ffprobe JSON output.
struct FfprobeOutput: Codable {
    let format: FfprobeFormat?
    let streams: [FfprobeStream]?
    let chapters: [FfprobeChapter]?
}

/// Format-level metadata from ffprobe.
struct FfprobeFormat: Codable {
    let filename: String?
    let formatName: String?
    let formatLongName: String?
    let duration: String?
    let size: String?
    let bitRate: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case filename
        case formatName = "format_name"
        case formatLongName = "format_long_name"
        case duration
        case size
        case bitRate = "bit_rate"
        case tags
    }

    var durationSeconds: Double? {
        duration.flatMap(Double.init)
    }
}

/// A single stream (audio, video, subtitle, etc.) from ffprobe.
struct FfprobeStream: Codable, Identifiable {
    let index: Int
    let codecType: String?
    let codecName: String?
    let codecLongName: String?
    let sampleRate: String?
    let channels: Int?
    let channelLayout: String?
    let bitsPerSample: Int?
    let width: Int?
    let height: Int?
    let rFrameRate: String?
    let duration: String?
    let bitRate: String?
    let tags: [String: String]?

    var id: Int { index }

    enum CodingKeys: String, CodingKey {
        case index
        case codecType = "codec_type"
        case codecName = "codec_name"
        case codecLongName = "codec_long_name"
        case sampleRate = "sample_rate"
        case channels
        case channelLayout = "channel_layout"
        case bitsPerSample = "bits_per_sample"
        case width, height
        case rFrameRate = "r_frame_rate"
        case duration
        case bitRate = "bit_rate"
        case tags
    }

    var isAudio: Bool { codecType == "audio" }
    var isVideo: Bool { codecType == "video" }

    var sampleRateHz: Double? {
        sampleRate.flatMap(Double.init)
    }

    var durationSeconds: Double? {
        duration.flatMap(Double.init)
    }
}

/// A chapter marker from ffprobe.
struct FfprobeChapter: Codable, Identifiable {
    let id: Int
    let startTime: String?
    let endTime: String?
    let tags: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id
        case startTime = "start_time"
        case endTime = "end_time"
        case tags
    }

    var title: String? { tags?["title"] }

    var startSeconds: Double? {
        startTime.flatMap(Double.init)
    }

    var endSeconds: Double? {
        endTime.flatMap(Double.init)
    }
}

// MARK: - Simplified MediaInfo

/// High-level summary of a media file, built from FfprobeOutput.
struct MediaInfo: Equatable {
    var url: URL
    var duration: Double
    var formatName: String
    var audioStreams: [AudioStreamInfo]
    var videoStreams: [VideoStreamInfo]
    var chapters: [ChapterInfo]
    var tags: [String: String]

    struct AudioStreamInfo: Equatable, Identifiable {
        let id: Int
        var codec: String
        var sampleRate: Double
        var channels: Int
        var bitDepth: Int
    }

    struct VideoStreamInfo: Equatable, Identifiable {
        let id: Int
        var codec: String
        var width: Int
        var height: Int
        var frameRate: String
    }

    struct ChapterInfo: Equatable, Identifiable {
        let id: Int
        var title: String
        var startTime: Double
        var endTime: Double
    }
}

extension MediaInfo {
    /// Build a MediaInfo from raw ffprobe output.
    static func from(url: URL, output: FfprobeOutput) -> MediaInfo {
        let format = output.format
        let streams = output.streams ?? []
        let chapters = output.chapters ?? []

        let audioStreams = streams
            .filter { $0.isAudio }
            .map { s in
                AudioStreamInfo(
                    id: s.index,
                    codec: s.codecName ?? "unknown",
                    sampleRate: s.sampleRateHz ?? 0,
                    channels: s.channels ?? 0,
                    bitDepth: s.bitsPerSample ?? 0
                )
            }

        let videoStreams = streams
            .filter { $0.isVideo }
            .map { s in
                VideoStreamInfo(
                    id: s.index,
                    codec: s.codecName ?? "unknown",
                    width: s.width ?? 0,
                    height: s.height ?? 0,
                    frameRate: s.rFrameRate ?? "0"
                )
            }

        let chapterInfos = chapters.map { c in
            ChapterInfo(
                id: c.id,
                title: c.title ?? "Chapter \(c.id + 1)",
                startTime: c.startSeconds ?? 0,
                endTime: c.endSeconds ?? 0
            )
        }

        return MediaInfo(
            url: url,
            duration: format?.durationSeconds ?? 0,
            formatName: format?.formatName ?? "unknown",
            audioStreams: audioStreams,
            videoStreams: videoStreams,
            chapters: chapterInfos,
            tags: format?.tags ?? [:]
        )
    }
}
