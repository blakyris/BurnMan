import CoreTransferable
import Foundation
import UniformTypeIdentifiers

// MARK: - Data File

struct DataFile: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var name: String
    var fileSize: UInt64
    var isDirectory: Bool
    var order: Int

    var fileSizeMB: Double {
        Double(fileSize) / 1_048_576.0
    }

    var fileExtension: String {
        isDirectory ? "" : url.pathExtension.lowercased()
    }

    var icon: String {
        isDirectory ? "folder" : "doc"
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: DataFile, rhs: DataFile) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Data File Transfer (for drag-and-drop reorder)

struct DataFileTransfer: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dataFileID)
    }
}

extension UTType {
    static let dataFileID = UTType(exportedAs: "org.burnman.datafile-id")
}

// MARK: - Data CD Settings

struct DataCDSettings: Equatable {
    var speed: Int = 8
    var simulate: Bool = false
    var eject: Bool = true
    var overburn: Bool = false
    var multiSession: Bool = false
    var cdCapacity: DataCDCapacity = .mb700

    static let availableSpeeds = [1, 2, 4, 8, 16, 24, 32, 48]
}

// MARK: - Data CD Capacity

enum DataCDCapacity: Equatable, CaseIterable, Identifiable {
    case mb650
    case mb700

    var id: String { displayName }

    var bytes: UInt64 {
        switch self {
        case .mb650: return 681_574_400
        case .mb700: return 734_003_200
        }
    }

    var megabytes: Double {
        Double(bytes) / 1_048_576.0
    }

    var displayName: String {
        switch self {
        case .mb650: return "650 MB (74 min)"
        case .mb700: return "700 MB (80 min)"
        }
    }
}

// MARK: - Data CD Phase

enum DataCDPhase: Equatable {
    case idle
    case validating
    case creatingISO
    case burning
    case verifying
    case cleaningUp
    case completed
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .validating: return "Validating..."
        case .creatingISO: return "Creating ISO..."
        case .burning: return "Burning..."
        case .verifying: return "Verifying..."
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

// MARK: - Data CD Progress

struct DataCDProgress: Equatable {
    var phase: DataCDPhase = .idle
    var isoPercent: Double = 0
    var burnPercent: Double = 0
    var elapsedSeconds: Int = 0
    var fifoPercent: Int = 0
    var isSimulation: Bool = false
    var writeSpeed: String? = nil
    var warnings: [String] = []

    var overallPercentage: Double {
        switch phase {
        case .idle: return 0
        case .validating: return 2
        case .creatingISO: return 3 + isoPercent * 0.20
        case .burning: return 25 + burnPercent * 0.65
        case .verifying: return 92
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
