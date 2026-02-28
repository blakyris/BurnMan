import Foundation

/// Pure utility for generating disc descriptor files (TOC, CUE).
/// No dependencies — works with generic input types.
enum DiscDescriptor {
    struct AudioTrackDescriptor {
        var wavFileName: String
        var title: String
        var artist: String
        var songwriter: String
        var message: String
        var isrc: String
    }

    struct DiscCDText {
        var albumTitle: String
        var albumArtist: String
        var albumSongwriter: String
        var albumMessage: String
    }

    /// Generates a cdrdao-compatible TOC file content.
    static func generateToc(tracks: [AudioTrackDescriptor], cdText: DiscCDText) -> String {
        var toc = "CD_DA\n\n"

        // Determine which CD-TEXT fields are used anywhere (disc or any track)
        let needsTitle = !cdText.albumTitle.isEmpty || tracks.contains { !$0.title.isEmpty }
        let needsPerformer = !cdText.albumArtist.isEmpty || tracks.contains { !$0.artist.isEmpty }
        let needsSongwriter = !cdText.albumSongwriter.isEmpty || tracks.contains { !$0.songwriter.isEmpty }
        let needsMessage = !cdText.albumMessage.isEmpty || tracks.contains { !$0.message.isEmpty }
        let hasAnyCDText = needsTitle || needsPerformer || needsSongwriter || needsMessage

        // Disc-level CD_TEXT
        if hasAnyCDText {
            toc += "CD_TEXT {\n"
            toc += "  LANGUAGE_MAP { 0 : EN }\n"
            toc += "  LANGUAGE 0 {\n"
            if needsTitle     { toc += "    TITLE \"\(escapeTOCString(cdText.albumTitle))\"\n" }
            if needsPerformer { toc += "    PERFORMER \"\(escapeTOCString(cdText.albumArtist))\"\n" }
            if needsSongwriter { toc += "    SONGWRITER \"\(escapeTOCString(cdText.albumSongwriter))\"\n" }
            if needsMessage   { toc += "    MESSAGE \"\(escapeTOCString(cdText.albumMessage))\"\n" }
            toc += "  }\n"
            toc += "}\n\n"
        }

        // Tracks
        for track in tracks {
            toc += "TRACK AUDIO\n"

            // Per-track ISRC (outside CD_TEXT block)
            if !track.isrc.isEmpty {
                toc += "  ISRC \"\(track.isrc)\"\n"
            }

            // Per-track CD-Text: emit ALL fields used anywhere for consistency
            if hasAnyCDText {
                toc += "  CD_TEXT {\n"
                toc += "    LANGUAGE 0 {\n"
                if needsTitle     { toc += "      TITLE \"\(escapeTOCString(track.title))\"\n" }
                if needsPerformer { toc += "      PERFORMER \"\(escapeTOCString(track.artist))\"\n" }
                if needsSongwriter { toc += "      SONGWRITER \"\(escapeTOCString(track.songwriter))\"\n" }
                if needsMessage   { toc += "      MESSAGE \"\(escapeTOCString(track.message))\"\n" }
                toc += "    }\n"
                toc += "  }\n"
            }

            toc += "  AUDIOFILE \"\(track.wavFileName)\" 0\n\n"
        }

        return toc
    }

    /// Escapes a string for cdrdao TOC format.
    /// cdrdao treats "" as "not defined" — uses a space to satisfy the requirement
    /// that a field be present for all tracks/disc.
    static func escapeTOCString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
                       .replacingOccurrences(of: "\"", with: "\\\"")
        return escaped.isEmpty ? " " : escaped
    }
}
