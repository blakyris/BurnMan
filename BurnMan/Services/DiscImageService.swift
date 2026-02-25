import Foundation

/// Reads optical discs to image files.
///
/// - Unencrypted DVD/BD: raw read via `dd` (requires root, runs through HelperClient)
/// - Encrypted DVD (CSS): read via ffmpeg's `dvdvideo` demuxer (uses libdvdnav → libdvdread → libdvdcss)
/// - CD: delegates to CompactDiscService (cdrdao read-cd)
class DiscImageService: @unchecked Sendable {
    private let helperClient: HelperClient
    private let toolRunner: ToolRunner
    let decryptionService: DecryptionService

    init(
        helperClient: HelperClient,
        toolRunner: ToolRunner,
        decryptionService: DecryptionService
    ) {
        self.helperClient = helperClient
        self.toolRunner = toolRunner
        self.decryptionService = decryptionService
    }

    // MARK: - Raw ISO Read (dd)

    /// Reads a disc to ISO using `dd`. Requires root (HelperClient).
    /// Works for unencrypted DVD and Blu-ray discs.
    ///
    /// - Parameters:
    ///   - bsdName: BSD device name, e.g. "disk4"
    ///   - outputPath: Absolute path for the output ISO file
    ///   - logPath: Path for progress log file
    /// - Returns: Exit code and error message
    func readToISO(
        bsdName: String,
        outputPath: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        await helperClient.runToolWithProgress(
            toolPath: ToolPaths.dd,
            arguments: ["if=/dev/\(bsdName)", "of=\(outputPath)", "bs=2048"],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: logPath
        )
    }

    // MARK: - Encrypted DVD Read (ffmpeg dvdvideo)

    /// Reads a CSS-encrypted DVD title using ffmpeg's dvdvideo demuxer.
    /// Requires libdvdnav + libdvdread compiled into ffmpeg, and libdvdcss installed by user.
    ///
    /// - Parameters:
    ///   - bsdName: BSD device name, e.g. "disk4"
    ///   - titleNumber: DVD title number (1-based, default main title)
    ///   - outputPath: Absolute path for the output file
    ///   - onLine: Callback for each output line (progress parsing)
    /// - Returns: Exit code (0 = success)
    func readEncryptedDVD(
        bsdName: String,
        titleNumber: Int = 1,
        outputPath: String,
        onLine: @escaping @MainActor (String) -> Void
    ) async -> Int32 {
        let args = [
            "-f", "dvdvideo",
            "-title", "\(titleNumber)",
            "-i", "/dev/\(bsdName)",
            "-codec", "copy",
            "-y", outputPath,
        ]

        return await toolRunner.run(
            executablePath: ToolPaths.ffmpeg,
            arguments: args,
            onLine: onLine
        )
    }

    // MARK: - Cancel

    func cancel() {
        Task { @MainActor in
            toolRunner.cancel()
        }
    }
}
