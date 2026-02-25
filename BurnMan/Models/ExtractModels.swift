import Foundation

// MARK: - Audio Output Format

/// Format de sortie pour l'extraction audio.
enum AudioOutputFormat: String, CaseIterable, Identifiable {
    case wav
    case mp3
    case flac
    case aac

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .wav:  return "WAV (sans perte)"
        case .mp3:  return "MP3"
        case .flac: return "FLAC (sans perte)"
        case .aac:  return "AAC"
        }
    }
}

// MARK: - CD Track Entry

/// Piste audio lue depuis le TOC d'un CD.
struct CDTrackEntry: Identifiable, Equatable {
    let id: Int
    var title: String
    var artist: String
    var durationSeconds: Double
    var selected: Bool = true

    var durationFormatted: String {
        let min = Int(durationSeconds) / 60
        let sec = Int(durationSeconds) % 60
        return String(format: "%d:%02d", min, sec)
    }
}

// MARK: - Video Output Format

/// Format de sortie pour l'extraction video.
enum VideoOutputFormat: String, CaseIterable, Identifiable {
    case mkv
    case mp4

    var id: String { rawValue }

    var fileExtension: String { rawValue }

    var displayName: String {
        switch self {
        case .mkv: return "MKV (remux, rapide)"
        case .mp4: return "MP4 (transcodage H.264)"
        }
    }

    var codec: String {
        switch self {
        case .mkv: return "copy"
        case .mp4: return "libx264"
        }
    }
}

// MARK: - DVD Title

/// Titre DVD detecte par ffprobe.
struct DVDTitle: Identifiable, Equatable {
    let id: Int
    var duration: Double
    var chapters: Int
    var audioStreams: [String]
    var subtitleStreams: [String]

    var durationFormatted: String {
        let hours = Int(duration) / 3600
        let min = (Int(duration) % 3600) / 60
        let sec = Int(duration) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, min, sec)
        }
        return String(format: "%d:%02d", min, sec)
    }
}
