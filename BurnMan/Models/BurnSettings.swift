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
            ("Vitesse", "\(speed)x"),
            ("Mode raw", rawMode ? "Oui" : "Non"),
            ("Swap audio", swapAudio ? "Oui" : "Non"),
            ("Simulation", simulate ? "Oui" : "Non"),
            ("Éjection", eject ? "Oui" : "Non"),
        ]
        if overburn {
            items.append(("Overburn", "Oui"))
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
        case .idle: return "En attente"
        case .preparing: return "Préparation..."
        case .starting: return "Démarrage..."
        case .pausing: return "Pause avant gravure..."
        case .blanking: return "Effacement du disque..."
        case .calibrating: return "Calibration..."
        case .writingLeadIn: return "Écriture du lead-in..."
        case .writingTrack(let n): return "Écriture piste \(n)..."
        case .writingLeadOut: return "Écriture du lead-out..."
        case .flushing: return "Flushing..."
        case .completed: return "Terminé !"
        case .failed(let msg): return "Erreur : \(msg)"
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
