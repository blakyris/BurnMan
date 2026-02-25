import Foundation

/// Stateless wrapper around cdrdao. All methods execute via HelperClient (root required).
class CompactDiscService: @unchecked Sendable {
    private let helperClient: HelperClient

    init(helperClient: HelperClient) {
        self.helperClient = helperClient
    }

    // MARK: - Read Operations

    /// Shows the TOC of a disc.
    func showTOC(device: String) async -> (output: String, exitCode: Int32) {
        await run(["show-toc", "--device", device])
    }

    /// Reads the TOC and saves it to a file.
    func readTOC(device: String, outputFile: String) async -> (output: String, exitCode: Int32) {
        await run(["read-toc", "--device", device, outputFile])
    }

    /// Full disc extraction (TOC + audio data).
    func readCD(device: String, outputFile: String) async -> (output: String, exitCode: Int32) {
        await run(["read-cd", "--device", device, outputFile])
    }

    /// Test read without writing.
    func readTest(device: String) async -> (output: String, exitCode: Int32) {
        await run(["read-test", "--device", device])
    }

    // MARK: - Write Operations

    /// Burns a disc in disc-at-once mode.
    func write(
        tocFile: String,
        device: String,
        simulate: Bool = false,
        speed: Int? = nil,
        overburn: Bool = false,
        bufferUnderrunProtection: Bool = true,
        eject: Bool = true,
        reload: Bool = false,
        onTheFly: Bool = false,
        workingDirectory: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args = [simulate ? "simulate" : "write"]
        args += ["--device", device]
        if let speed { args += ["--speed", "\(speed)"] }
        if overburn { args.append("--overburn") }
        if eject { args.append("--eject") }
        if reload { args.append("--reload") }
        if onTheFly { args.append("--on-the-fly") }
        args.append(tocFile)

        return await runWithProgress(args, workingDirectory: workingDirectory, logPath: logPath)
    }

    /// Simulates a burn.
    func simulate(
        tocFile: String,
        device: String,
        speed: Int? = nil,
        workingDirectory: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args = ["simulate", "--device", device]
        if let speed { args += ["--speed", "\(speed)"] }
        args.append(tocFile)
        return await runWithProgress(args, workingDirectory: workingDirectory, logPath: logPath)
    }

    /// Copies a disc.
    func copy(sourceDevice: String, destDevice: String, onTheFly: Bool = false) async -> (output: String, exitCode: Int32) {
        var args = ["copy", "--source-device", sourceDevice, "--device", destDevice]
        if onTheFly { args.append("--on-the-fly") }
        return await run(args)
    }

    // MARK: - Disc Management

    /// Blanks a CD-RW.
    func blank(
        device: String,
        mode: BlankMode = .full,
        speed: Int? = nil,
        eject: Bool = true,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args = ["blank", "--device", device, "--blank-mode", mode.rawValue]
        if let speed { args += ["--speed", "\(speed)"] }
        if eject { args.append("--eject") }
        return await runWithProgress(args, workingDirectory: FileManager.default.temporaryDirectory.path, logPath: logPath)
    }

    /// Scans for available drives.
    func scanbus() async -> (output: String, exitCode: Int32) {
        await run(["scanbus"])
    }

    /// Gets disc information.
    func diskInfo(device: String) async -> (output: String, exitCode: Int32) {
        await run(["disk-info", "--device", device])
    }

    /// Unlocks the drive tray.
    func unlock(device: String) async -> (exitCode: Int32, errorMessage: String) {
        await runWithProgress(
            ["unlock", "--device", device],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: "/tmp/cdrburn_unlock.log"
        )
    }

    // MARK: - Cancel

    /// Cancels the current cdrdao process.
    func cancel() async -> Bool {
        await helperClient.cancelCurrentProcess()
    }

    // MARK: - Private

    private func run(_ arguments: [String]) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.cdrdao,
            arguments: arguments,
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    private func runWithProgress(
        _ arguments: [String],
        workingDirectory: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        await helperClient.runToolWithProgress(
            toolPath: ToolPaths.cdrdao,
            arguments: arguments,
            workingDirectory: workingDirectory,
            logPath: logPath
        )
    }
}

// MARK: - Supporting Types

enum BlankMode: String, CaseIterable, Identifiable {
    case full
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full:    return "Complet"
        case .minimal: return "Rapide"
        }
    }
}
