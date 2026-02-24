import Foundation

// MARK: - Track Mode

enum TrackMode: String, CaseIterable, Identifiable {
    case mode1 = "MODE1/2352"
    case mode2 = "MODE2/2352"
    case audio = "AUDIO"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mode1: return "Mode 1 (CD-ROM)"
        case .mode2: return "Mode 2 (PS1)"
        case .audio: return "Audio"
        }
    }

    var icon: String {
        switch self {
        case .mode1: return "opticaldisc"
        case .mode2: return "gamecontroller"
        case .audio: return "music.note"
        }
    }
}

// MARK: - Track Info

struct TrackInfo: Identifiable, Hashable {
    let id = UUID()
    var number: Int
    var mode: TrackMode
    var fileName: String
    var fileURL: URL?
    var startSector: Int
    var endSector: Int
    var sizeBytes: UInt64

    var sizeMB: Double {
        Double(sizeBytes) / 1_048_576.0
    }

    var durationSeconds: Int {
        let sectors = endSector - startSector + 1
        return sectors / CdrdaoConfig.sectorsPerSecond
    }

    var durationFormatted: String {
        let min = durationSeconds / 60
        let sec = durationSeconds % 60
        return String(format: "%02d:%02d", min, sec)
    }

    var msfStart: String {
        let ff = startSector % 75
        let ss = (startSector / 75) % 60
        let mm = startSector / 75 / 60
        return String(format: "%02d:%02d:%02d", mm, ss, ff)
    }
}

// MARK: - CUE File

struct CueFile: Identifiable {
    let id = UUID()
    var url: URL
    var tracks: [TrackInfo]

    var name: String {
        url.deletingPathExtension().lastPathComponent
    }

    var totalSizeMB: Double {
        tracks.reduce(0) { $0 + $1.sizeMB }
    }

    var trackCount: Int {
        tracks.count
    }

    var dataTrackCount: Int {
        tracks.filter { $0.mode != .audio }.count
    }

    var audioTrackCount: Int {
        tracks.filter { $0.mode == .audio }.count
    }
}
