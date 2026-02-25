import Foundation

/// Unified pipeline state used by all Managers.
enum PipelineState: Equatable {
    case idle
    case preparing
    case reading
    case extracting(current: Int, total: Int)
    case converting(current: Int, total: Int)
    case erasing
    case copying
    case burning
    case simulating
    case cancelling
    case finished
    case failed

    var displayName: String {
        switch self {
        case .idle:                            return "En attente"
        case .preparing:                       return "Préparation..."
        case .reading:                         return "Lecture du disque..."
        case .extracting(let cur, let tot):    return "Extraction \(cur)/\(tot)..."
        case .converting(let cur, let tot):    return "Conversion \(cur)/\(tot)..."
        case .erasing:                         return "Effacement..."
        case .copying:                         return "Copie..."
        case .burning:                         return "Gravure..."
        case .simulating:                      return "Simulation..."
        case .cancelling:                      return "Annulation..."
        case .finished:                        return "Terminé !"
        case .failed:                          return "Erreur"
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .finished, .failed: return false
        default: return true
        }
    }
}
