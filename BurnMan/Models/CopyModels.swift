import Foundation

// MARK: - Copy Mode

/// Mode de copie de disque.
enum CopyMode: String, CaseIterable, Identifiable {
    case discToDisc = "Disque a disque"
    case discToImage = "Disque vers image"

    var id: String { rawValue }
}

// MARK: - Image Output Format

/// Format de sortie pour la creation d'image disque.
enum ImageOutputFormat: String, CaseIterable, Identifiable {
    case iso
    case cueBin

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iso:    return "ISO"
        case .cueBin: return "CUE/BIN"
        }
    }

    var fileExtension: String {
        switch self {
        case .iso:    return "iso"
        case .cueBin: return "bin"
        }
    }
}
