import Foundation

// MARK: - Target Media

/// The physical media category for a disc project.
enum TargetMedia: String, CaseIterable, Identifiable {
    case cd
    case dvd
    case bluray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cd:      return "CD"
        case .dvd:     return "DVD"
        case .bluray:  return "Blu-ray"
        }
    }
}

// MARK: - Video Disc Type

/// The type of video disc to create.
enum VideoDiscType: String, CaseIterable, Identifiable {
    case dvd
    case bluray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dvd:     return "DVD-Vidéo"
        case .bluray:  return "Blu-ray"
        }
    }
}

// MARK: - Disc Image Type

/// Supported disc image formats.
enum DiscImageType: String, CaseIterable, Identifiable {
    case cueBin
    case iso
    case nrg
    case img

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cueBin:  return "CUE/BIN"
        case .iso:     return "ISO"
        case .nrg:     return "NRG (Nero)"
        case .img:     return "IMG"
        }
    }

    /// Detect image type from file extension.
    static func from(url: URL) -> DiscImageType? {
        switch url.pathExtension.lowercased() {
        case "cue":          return .cueBin
        case "iso":          return .iso
        case "nrg":          return .nrg
        case "img", "bin":   return .img
        default:             return nil
        }
    }
}

// MARK: - File System Type

/// File system to use for data discs.
enum FileSystemType: String, CaseIterable, Identifiable {
    case iso9660
    case udf
    case hybrid
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .iso9660: return "ISO 9660"
        case .udf:     return "UDF"
        case .hybrid:  return "ISO 9660 + UDF"
        case .auto:    return "Automatique"
        }
    }
}

// MARK: - Media Type

/// Physical media type detected in a drive.
enum MediaType: String, CaseIterable, Identifiable {
    case cdR, cdRW
    case dvdPlusR, dvdPlusRW, dvdPlusRDL
    case dvdMinusR, dvdMinusRW, dvdMinusRDL, dvdRam
    case bdR, bdRE
    case unknown

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cdR:          return "CD-R"
        case .cdRW:         return "CD-RW"
        case .dvdPlusR:     return "DVD+R"
        case .dvdPlusRW:    return "DVD+RW"
        case .dvdPlusRDL:   return "DVD+R DL"
        case .dvdMinusR:    return "DVD-R"
        case .dvdMinusRW:   return "DVD-RW"
        case .dvdMinusRDL:  return "DVD-R DL"
        case .dvdRam:       return "DVD-RAM"
        case .bdR:          return "BD-R"
        case .bdRE:         return "BD-RE"
        case .unknown:      return "Inconnu"
        }
    }

    var category: TargetMedia {
        switch self {
        case .cdR, .cdRW:
            return .cd
        case .dvdPlusR, .dvdPlusRW, .dvdPlusRDL,
             .dvdMinusR, .dvdMinusRW, .dvdMinusRDL, .dvdRam:
            return .dvd
        case .bdR, .bdRE:
            return .bluray
        case .unknown:
            return .cd
        }
    }

    var isRewritable: Bool {
        switch self {
        case .cdRW, .dvdPlusRW, .dvdMinusRW, .dvdRam, .bdRE:
            return true
        default:
            return false
        }
    }
}

// MARK: - Device Capability

/// Capabilities of an optical drive.
enum DeviceCapability: String, CaseIterable, Identifiable {
    case writeCD
    case writeDVD
    case writeBD
    case readOnly

    var id: String { rawValue }
}
