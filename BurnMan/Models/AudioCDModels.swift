import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Audio Track

struct AudioTrack: Identifiable, Hashable {
    let id = UUID()
    var sourceURL: URL
    var title: String
    var artist: String
    var songwriter: String
    var message: String
    var isrc: String
    var albumName: String
    var durationSeconds: Double
    var sourceFormat: String
    var sampleRate: Double
    var bitDepth: Int
    var channels: Int
    var order: Int
    var convertedURL: URL?

    var isCDQuality: Bool {
        sourceFormat.uppercased() == "WAV"
            && sampleRate == 44100
            && bitDepth == 16
            && channels == 2
    }

    var needsConversion: Bool { !isCDQuality }

    var durationFormatted: String {
        let min = Int(durationSeconds) / 60
        let sec = Int(durationSeconds) % 60
        return String(format: "%d:%02d", min, sec)
    }

    var cdSizeBytes: Int {
        Int(durationSeconds * Double(CdrdaoConfig.cdAudioBytesPerSecond))
    }

    var fileName: String {
        sourceURL.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Audio Track Transfer (for drag-and-drop reorder)

struct AudioTrackTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .audioTrackID)
    }
}

extension UTType {
    static let audioTrackID = UTType(exportedAs: "org.burnman.audiotrack-id")
}

// MARK: - CD-Text Metadata

struct CDTextMetadata: Equatable {
    var albumTitle: String = ""
    var albumArtist: String = ""
    var albumSongwriter: String = ""
    var albumMessage: String = ""
    var upcEan: String = ""
}

// MARK: - CD Type

enum CDType: String, CaseIterable, Identifiable {
    case min74 = "74 min"
    case min80 = "80 min"

    var id: String { rawValue }

    var maxSeconds: Int {
        switch self {
        case .min74: return CdrdaoConfig.cd74MaxSeconds
        case .min80: return CdrdaoConfig.cd80MaxSeconds
        }
    }
}

// MARK: - Audio CD Settings

struct AudioCDSettings: Equatable {
    var speed: Int = 8
    var simulate: Bool = false
    var eject: Bool = true
    var overburn: Bool = false
    var cdType: CDType = .min80

    static let availableSpeeds = [1, 2, 4, 8, 16, 24, 32, 48]
}

// MARK: - Audio CD Phase

enum AudioCDPhase: Equatable {
    case idle
    case validating
    case converting(current: Int, total: Int)
    case generatingTOC
    case burning
    case cleaningUp
    case completed
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .validating: return "Preparing..."
        case .converting(let cur, let tot): return "Converting \(cur)/\(tot)..."
        case .generatingTOC: return "Generating TOC..."
        case .burning: return "Burning..."
        case .cleaningUp: return "Cleaning up..."
        case .completed: return "Done!"
        case .failed(let msg): return "Error: \(msg)"
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .completed, .failed: return false
        default: return true
        }
    }
}

// MARK: - Audio CD Progress

struct AudioCDProgress: Equatable {
    var pipelinePhase: AudioCDPhase = .idle
    var conversionTrackIndex: Int = 0
    var conversionTotalTracks: Int = 0
    var conversionTrackProgress: Double = 0.0
    var burnPhase: BurnPhase = .idle
    var currentMB: Int = 0
    var totalMB: Int = 0
    var currentTrack: Int = 1
    var elapsedSeconds: Int = 0
    var bufferFillFIFO: Int = 0
    var bufferFillDrive: Int = 0
    var isSimulation: Bool = false
    var writeSpeed: String? = nil
    var warnings: [String] = []

    var overallPercentage: Double {
        switch pipelinePhase {
        case .idle: return 0
        case .validating: return 2
        case .converting(let cur, let tot):
            guard tot > 0 else { return 5 }
            let perTrack = 60.0 / Double(tot)
            return 5.0 + Double(cur - 1) * perTrack + conversionTrackProgress * perTrack
        case .generatingTOC: return 65
        case .burning:
            guard totalMB > 0 else { return 70 }
            return 70 + Double(currentMB) / Double(totalMB) * 25.0
        case .cleaningUp: return 97
        case .completed: return 100
        case .failed: return 0
        }
    }

    var elapsedFormatted: String {
        let min = elapsedSeconds / 60
        let sec = elapsedSeconds % 60
        return String(format: "%02d:%02d", min, sec)
    }
}
