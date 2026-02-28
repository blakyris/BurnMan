import Foundation

// MARK: - Burn Settings

struct BurnSettings {
    var speed: Int = 8
    var rawMode: Bool = false
    var swapAudio: Bool = false
    var simulate: Bool = false
    var eject: Bool = true
    var overburn: Bool = false

    static let availableSpeeds = [1, 2, 4, 8, 16, 24]

    init() {
        let defaults = UserDefaults.standard
        let storedSpeed = defaults.integer(forKey: "defaultSpeed")
        if Self.availableSpeeds.contains(storedSpeed) {
            self.speed = storedSpeed
        }
        self.rawMode = defaults.bool(forKey: "defaultRaw")
        self.swapAudio = defaults.bool(forKey: "defaultSwap")
        if defaults.object(forKey: "defaultEject") != nil {
            self.eject = defaults.bool(forKey: "defaultEject")
        }
    }

    var summary: [(String, String)] {
        var items: [(String, String)] = [
            ("Speed", "\(speed)x"),
            ("Raw mode", rawMode ? "Yes" : "No"),
            ("Swap audio", swapAudio ? "Yes" : "No"),
            ("Simulation", simulate ? "Yes" : "No"),
            ("Eject", eject ? "Yes" : "No"),
        ]
        if overburn {
            items.append(("Overburn", "Yes"))
        }
        return items
    }
}

// MARK: - Burn State

enum BurnPhase: Equatable {
    case idle
    case preparing
    case starting
    case pausing
    case blanking
    case calibrating
    case writingLeadIn
    case writingTrack(Int)
    case writingLeadOut
    case flushing
    case completed
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .preparing: return "Preparing..."
        case .starting: return "Starting..."
        case .pausing: return "Pausing before burn..."
        case .blanking: return "Erasing disc..."
        case .calibrating: return "Calibrating..."
        case .writingLeadIn: return "Writing lead-in..."
        case .writingTrack(let n): return "Writing track \(n)..."
        case .writingLeadOut: return "Writing lead-out..."
        case .flushing: return "Flushing..."
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

struct BurnProgress: Equatable {
    var phase: BurnPhase = .idle
    var currentMB: Int = 0
    var totalMB: Int = 0
    var currentTrack: Int = 1
    var elapsedSeconds: Int = 0
    var bufferFillFIFO: Int = 0
    var bufferFillDrive: Int = 0
    var isSimulation: Bool = false
    var writeSpeed: String? = nil
    var warnings: [String] = []

    var percentage: Double {
        guard totalMB > 0 else { return 0 }
        return Double(currentMB) / Double(totalMB) * 100
    }

    var etaSeconds: Int {
        guard currentMB > 0, elapsedSeconds > 2 else { return 0 }
        return (totalMB - currentMB) * elapsedSeconds / currentMB
    }

    var etaFormatted: String {
        let min = etaSeconds / 60
        let sec = etaSeconds % 60
        return String(format: "%02d:%02d", min, sec)
    }

    var elapsedFormatted: String {
        let min = elapsedSeconds / 60
        let sec = elapsedSeconds % 60
        return String(format: "%02d:%02d", min, sec)
    }
}
