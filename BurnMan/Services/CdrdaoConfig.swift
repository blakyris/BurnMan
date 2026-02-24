import Foundation

enum CdrdaoConfig {
    // CD constants (Red Book)
    static let sectorSize = 2352
    static let sectorsPerSecond = 75
    static let defaultPregapSectors = 150
    static let progressReportInterval = 5000 // sectors between progress callbacks

    // CD Audio constants
    static let cdAudioBytesPerSecond = 176_400  // 44100 * 2 * 2
    static let cd74MaxSeconds = 4440             // 74 min
    static let cd80MaxSeconds = 4800             // 80 min

    static var resolvedPath: String {
        guard let frameworksPath = Bundle.main.privateFrameworksPath else {
            fatalError("cdrdao non trouvé dans le bundle")
        }
        return (frameworksPath as NSString).appendingPathComponent("cdrdao")
    }

    // Valid cdrdao subcommands (from man page)
    static let validCommands: Set<String> = [
        "write", "simulate", "copy", "read-toc", "read-cd",
        "read-test", "show-toc", "scanbus", "disk-info", "blank", "unlock"
    ]
}
