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
        case .idle:                            return "Idle"
        case .preparing:                       return "Preparing..."
        case .reading:                         return "Reading disc..."
        case .extracting(let cur, let tot):    return "Extracting \(cur)/\(tot)..."
        case .converting(let cur, let tot):    return "Converting \(cur)/\(tot)..."
        case .erasing:                         return "Erasing..."
        case .copying:                         return "Copying..."
        case .burning:                         return "Burning..."
        case .simulating:                      return "Simulating..."
        case .cancelling:                      return "Cancelling..."
        case .finished:                        return "Done!"
        case .failed:                          return "Error"
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .finished, .failed: return false
        default: return true
        }
    }
}
