import Foundation

// MARK: - CUE Generator

class CueGenerator {

    static let sectorSize = CdrdaoConfig.sectorSize
    static let syncPattern: [UInt8] = [0x00] + Array(repeating: 0xFF, count: 10) + [0x00]

    // MARK: - Detect mode of a single .bin file

    static func detectMode(at url: URL) throws -> TrackMode {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let headerData = handle.readData(ofLength: 16)
        guard headerData.count >= 16 else { return .audio }

        let syncBytes = Array(headerData.prefix(12))
        if syncBytes == syncPattern {
            let modeByte = headerData[15]
            switch modeByte {
            case 1: return .mode1
            case 2: return .mode2
            default: return .mode1
            }
        } else {
            return .audio
        }
    }

    // MARK: - Scan multi-track .bin file

    static func scanMultiTrack(
        at url: URL,
        progress: @escaping (Double) -> Void
    ) throws -> [TrackInfo] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
        let totalSectors = Int(fileSize) / sectorSize

        var tracks: [TrackInfo] = []
        var currentType: TrackMode?
        var trackStart = 0

        for sector in 0..<totalSectors {
            // Progression
            if sector % CdrdaoConfig.progressReportInterval == 0 {
                progress(Double(sector) / Double(totalSectors))
            }

            handle.seek(toFileOffset: UInt64(sector * sectorSize))
            let sectorData = handle.readData(ofLength: min(16, sectorSize))

            guard sectorData.count >= 12 else { break }

            let sectorType: TrackMode
            let syncBytes = Array(sectorData.prefix(12))

            if syncBytes == syncPattern && sectorData.count >= 16 {
                let modeByte = sectorData[15]
                sectorType = modeByte == 1 ? .mode1 : .mode2
            } else {
                sectorType = .audio
            }

            if sectorType != currentType {
                if let prevType = currentType {
                    let sectorCount = sector - trackStart
                    tracks.append(TrackInfo(
                        number: tracks.count + 1,
                        mode: prevType,
                        fileName: url.lastPathComponent,
                        fileURL: url,
                        startSector: trackStart,
                        endSector: sector - 1,
                        sizeBytes: UInt64(sectorCount * sectorSize)
                    ))
                }
                currentType = sectorType
                trackStart = sector
            }
        }

        // Dernière piste
        if let lastType = currentType {
            let sectorCount = totalSectors - trackStart
            tracks.append(TrackInfo(
                number: tracks.count + 1,
                mode: lastType,
                fileName: url.lastPathComponent,
                fileURL: url,
                startSector: trackStart,
                endSector: totalSectors - 1,
                sizeBytes: UInt64(sectorCount * sectorSize)
            ))
        }

        progress(1.0)
        return tracks
    }

    // MARK: - Analyze multiple .bin files

    static func analyzeMultipleFiles(urls: [URL]) throws -> [TrackInfo] {
        // Trier par nom/numéro de piste
        let sorted = urls.sorted { extractTrackNumber(from: $0) < extractTrackNumber(from: $1) }

        return try sorted.enumerated().map { index, url in
            let mode = try detectMode(at: url)
            let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 ?? 0
            let totalSectors = Int(fileSize) / sectorSize

            return TrackInfo(
                number: index + 1,
                mode: mode,
                fileName: url.lastPathComponent,
                fileURL: url,
                startSector: 0,
                endSector: totalSectors - 1,
                sizeBytes: fileSize
            )
        }
    }

    // MARK: - Generate .cue content

    static func generateCueContent(tracks: [TrackInfo], isMultiTrack: Bool) -> String {
        var lines: [String] = []

        if isMultiTrack {
            // Toutes les pistes dans un seul fichier
            guard let fileName = tracks.first?.fileName else { return "" }
            lines.append("FILE \"\(fileName)\" BINARY")

            for track in tracks {
                lines.append("  TRACK \(String(format: "%02d", track.number)) \(track.mode.rawValue)")

                // Pregap pour les pistes audio après la première
                if track.number > 1 && track.mode == .audio {
                    let pregapSector = max(0, track.startSector - CdrdaoConfig.defaultPregapSectors)
                    lines.append("    INDEX 00 \(sectorToMSF(pregapSector))")
                }

                lines.append("    INDEX 01 \(track.msfStart)")
            }
        } else {
            // Fichiers séparés
            for track in tracks {
                lines.append("FILE \"\(track.fileName)\" BINARY")
                lines.append("  TRACK \(String(format: "%02d", track.number)) \(track.mode.rawValue)")
                lines.append("    INDEX 01 00:00:00")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Write .cue file

    static func writeCueFile(content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Helpers

    private static func extractTrackNumber(from url: URL) -> Int {
        let name = url.deletingPathExtension().lastPathComponent
        let pattern = try? NSRegularExpression(pattern: "(?:track|t|piste)[\\s_.-]?(\\d+)", options: .caseInsensitive)
        let range = NSRange(name.startIndex..., in: name)

        if let match = pattern?.firstMatch(in: name, range: range),
           let numRange = Range(match.range(at: 1), in: name) {
            return Int(name[numRange]) ?? 0
        }

        // Fallback : dernier nombre dans le nom
        let numPattern = try? NSRegularExpression(pattern: "(\\d+)")
        let matches = numPattern?.matches(in: name, range: range) ?? []
        if let lastMatch = matches.last,
           let numRange = Range(lastMatch.range(at: 1), in: name) {
            return Int(name[numRange]) ?? 0
        }

        return 0
    }

    private static func sectorToMSF(_ sector: Int) -> String {
        let ff = sector % 75
        let ss = (sector / 75) % 60
        let mm = sector / 75 / 60
        return String(format: "%02d:%02d:%02d", mm, ss, ff)
    }
}
