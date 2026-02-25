import Foundation

/// Stateless wrapper around dvd+rw-tools (growisofs, dvd+rw-format, dvd+rw-mediainfo, dvd+rw-booktype).
/// All methods execute via HelperClient (root required).
class DVDService: @unchecked Sendable {
    private let helperClient: HelperClient

    init(helperClient: HelperClient) {
        self.helperClient = helperClient
    }

    // MARK: - Burn Operations

    /// Burns an ISO image or directory to DVD/BD.
    func burn(
        isoPath: String,
        device: String,
        speed: Int? = nil,
        dvdCompat: Bool = false,
        dryRun: Bool = false,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args = ["-Z", "\(device)=\(isoPath)"]
        if let speed { args.append("-speed=\(speed)") }
        if dvdCompat { args.append("-dvd-compat") }
        if dryRun { args.append("-dry-run") }

        return await runGrowisofs(args, logPath: logPath)
    }

    /// Appends a session to a multi-session DVD.
    func appendSession(
        isoPath: String,
        device: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        await runGrowisofs(["-M", "\(device)=\(isoPath)"], logPath: logPath)
    }

    /// Burns via pipe (mkisofs-style arguments).
    func burnOnTheFly(
        mkisofsArgs: [String],
        device: String,
        speed: Int? = nil,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args = ["-Z", "\(device)"]
        if let speed { args.append("-speed=\(speed)") }
        args += mkisofsArgs

        return await runGrowisofs(args, logPath: logPath)
    }

    // MARK: - Format Operations

    /// Formats DVD+RW / BD-RE.
    func format(
        device: String,
        force: Bool = false,
        leadOut: Bool = false,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args = [device]
        if force { args.append("-force") }
        if leadOut { args.append("-lead-out") }

        return await helperClient.runToolWithProgress(
            toolPath: ToolPaths.dvdRwFormat,
            arguments: args,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: logPath
        )
    }

    /// Blanks DVD-RW (sequential).
    func blankDVDRW(device: String, logPath: String) async -> (exitCode: Int32, errorMessage: String) {
        await helperClient.runToolWithProgress(
            toolPath: ToolPaths.dvdRwFormat,
            arguments: ["-blank", device],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: logPath
        )
    }

    // MARK: - Info Operations

    /// Gets detailed media information.
    func mediaInfo(device: String) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.dvdRwMediainfo,
            arguments: [device],
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    /// Changes the booktype (bitsetting).
    func setBooktype(device: String, booktype: String) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.dvdRwBooktype,
            arguments: ["-dvd+r-booktype=\(booktype)", device],
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    // MARK: - Cancel

    func cancel() async -> Bool {
        await helperClient.cancelCurrentProcess()
    }

    // MARK: - Private

    private func runGrowisofs(
        _ arguments: [String],
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        await helperClient.runToolWithProgress(
            toolPath: ToolPaths.growisofs,
            arguments: arguments,
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: logPath
        )
    }
}
