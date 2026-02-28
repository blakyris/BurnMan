import Foundation

/// Creates and manipulates ISO images. Runs locally via ToolRunner (no root required).
class DiscAuthoringService: @unchecked Sendable {
    private let toolRunner = ToolRunner()

    /// Creates an ISO image from a staging directory using mkisofs.
    /// - Parameters:
    ///   - sourceDirectory: Path to the directory whose contents become the ISO root.
    ///   - outputPath: Where to write the ISO file.
    ///   - volumeLabel: Volume label for the ISO.
    ///   - joliet: Enable Joliet extensions (Windows compatibility).
    ///   - rockRidge: Enable Rock Ridge extensions (Unix permissions).
    ///   - onLine: Called for each line of mkisofs output (progress, errors).
    /// - Returns: The mkisofs exit code (0 = success).
    @MainActor
    func createISO(
        sourceDirectory: String,
        outputPath: String,
        volumeLabel: String,
        joliet: Bool = true,
        rockRidge: Bool = true,
        onLine: @escaping @MainActor (String) -> Void
    ) async -> Int32 {
        var args: [String] = []

        if joliet { args.append("-J") }
        if rockRidge { args.append("-r") }
        args += ["-V", volumeLabel]
        args += ["-o", outputPath]
        args.append(sourceDirectory)

        return await toolRunner.run(
            executablePath: ToolPaths.mkisofs,
            arguments: args,
            onLine: onLine
        )
    }

    /// Cancels the current mkisofs process.
    @MainActor
    func cancel() {
        toolRunner.cancel()
    }
}
