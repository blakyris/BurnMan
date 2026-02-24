import Foundation

/// Centralized CLI process execution.
/// - `run(onLine:)` — Streaming: long-running processes (ffmpeg, cdrdao).
///   Merges stdout/stderr, normalizes \r→\n, delivers lines on MainActor.
/// - `collect()` — One-shot: returns complete stdout (ffprobe).
///   stderr discarded, no line splitting.
@MainActor
class ToolRunner {
    private(set) var isRunning = false
    private var process: Process?

    /// If the executable lives inside the app bundle's Frameworks directory,
    /// returns an environment with DYLD_LIBRARY_PATH set so bundled dylibs are found.
    private static func environmentForBundledTool(at path: String) -> [String: String]? {
        guard let frameworksPath = Bundle.main.privateFrameworksPath,
              path.hasPrefix(frameworksPath) else { return nil }
        var env = ProcessInfo.processInfo.environment
        env["DYLD_LIBRARY_PATH"] = frameworksPath
        return env
    }

    // MARK: - Streaming

    /// Runs `executablePath` with `arguments`, merging stdout and stderr.
    /// Splits `\r` into `\n` for cdrdao-style carriage-return progress lines.
    /// Calls `onLine` on the MainActor for each non-empty line.
    ///
    /// - Parameters:
    ///   - executablePath: Absolute path to the binary.
    ///   - arguments: Command-line arguments.
    ///   - currentDirectory: Optional working directory.
    ///   - onLine: Called on MainActor for every non-empty output line.
    /// - Returns: The process exit code (0 = success, -1 = launch failure).
    func run(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        onLine: @escaping @MainActor (String) -> Void
    ) async -> Int32 {
        let proc = Process()
        let pipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        if let dir = currentDirectory {
            proc.currentDirectoryURL = dir
        }
        if let env = Self.environmentForBundledTool(at: executablePath) {
            proc.environment = env
        }
        proc.standardOutput = pipe
        proc.standardError = pipe
        self.process = proc
        isRunning = true

        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let output = String(data: data, encoding: .utf8) else { return }

            let lines = output
                .replacingOccurrences(of: "\r", with: "\n")
                .components(separatedBy: "\n")
                .filter { !$0.isEmpty }

            Task { @MainActor in
                for line in lines { onLine(line) }
            }
        }

        let exitCode: Int32
        do {
            exitCode = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int32, any Error>) in

                proc.terminationHandler = { @Sendable terminatedProc in
                    pipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }

                do {
                    try proc.run()
                    ProcessTracker.shared.register(proc)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            isRunning = false
            return -1
        }

        ProcessTracker.shared.unregister(proc)
        isRunning = false
        return exitCode
    }

    // MARK: - Collect

    /// Runs a command and returns its complete stdout as Data.
    /// stderr is sent to /dev/null. No line splitting.
    /// Reads pipe on a detached task to avoid buffer deadlock.
    func collect(
        executablePath: String,
        arguments: [String],
        currentDirectory: URL? = nil
    ) async -> (exitCode: Int32, data: Data) {
        let proc = Process()
        let stdoutPipe = Pipe()

        proc.executableURL = URL(fileURLWithPath: executablePath)
        proc.arguments = arguments
        if let dir = currentDirectory {
            proc.currentDirectoryURL = dir
        }
        if let env = Self.environmentForBundledTool(at: executablePath) {
            proc.environment = env
        }
        proc.standardOutput = stdoutPipe
        proc.standardError = FileHandle.nullDevice
        self.process = proc
        isRunning = true

        // Read pipe on background to prevent buffer deadlock
        let readTask = Task.detached {
            stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        }

        let exitCode: Int32
        do {
            exitCode = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int32, any Error>) in
                proc.terminationHandler = { @Sendable terminatedProc in
                    continuation.resume(returning: terminatedProc.terminationStatus)
                }
                do {
                    try proc.run()
                    ProcessTracker.shared.register(proc)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } catch {
            isRunning = false
            readTask.cancel()
            return (-1, Data())
        }

        ProcessTracker.shared.unregister(proc)
        let data = await readTask.value
        isRunning = false
        return (exitCode, data)
    }

    // MARK: - Cancel

    func cancel() {
        process?.terminate()
    }
}
