import Foundation
import Synchronization

// MARK: - Helper Delegate

class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection newConnection: NSXPCConnection
    ) -> Bool {
        // In production, add your Team ID:
        // "identifier \"org.burnman.app\" and certificate leaf[subject.OU] = \"YOUR_TEAM_ID\""
        newConnection.setCodeSigningRequirement("identifier \"org.burnman.app\"")

        newConnection.exportedInterface = NSXPCInterface(with: BurnManHelperProtocol.self)
        newConnection.exportedObject = HelperTool()

        newConnection.invalidationHandler = { }

        newConnection.resume()
        return true
    }
}

// MARK: - Helper Tool (executes CLI tools as root)

class HelperTool: NSObject, BurnManHelperProtocol {

    private let currentProcess = Mutex<Process?>(nil)

    func ping(reply: @escaping (String) -> Void) {
        reply(BurnManHelperConstants.helperVersion)
    }

    func runTool(
        toolPath: String,
        arguments: [String],
        workingDirectory: String,
        reply: @escaping (String, Int32) -> Void
    ) {
        guard validateToolPath(toolPath) else {
            reply("Chemin outil non autorisé : \(toolPath)", -1)
            return
        }

        guard validateArguments(arguments, toolPath: toolPath) else {
            reply("Arguments invalides ou caractères interdits", -2)
            return
        }

        guard validateWorkingDirectory(workingDirectory) else {
            reply("Répertoire de travail invalide : \(workingDirectory)", -3)
            return
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = buildEnvironment(forToolAt: toolPath)

        let outputData = Mutex(Data())

        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            outputData.withLock { $0.append(data) }
        }

        do {
            try process.run()
            currentProcess.withLock { $0 = process }
            process.waitUntilExit()
            currentProcess.withLock { $0 = nil }

            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain remaining data
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if !remaining.isEmpty {
                outputData.withLock { $0.append(remaining) }
            }

            let output = outputData.withLock { String(data: $0, encoding: .utf8) ?? "" }
            reply(output, process.terminationStatus)
        } catch {
            currentProcess.withLock { $0 = nil }
            pipe.fileHandleForReading.readabilityHandler = nil
            reply("Impossible de lancer l'outil : \(error.localizedDescription)", -5)
        }
    }

    func runToolWithProgress(
        toolPath: String,
        arguments: [String],
        workingDirectory: String,
        logPath: String,
        reply: @escaping (Int32, String) -> Void
    ) {
        guard validateToolPath(toolPath) else {
            let msg = "Chemin outil non autorisé : \(toolPath)"
            reply(-1, msg)
            return
        }

        guard validateArguments(arguments, toolPath: toolPath) else {
            let msg = "Arguments invalides ou caractères interdits"
            writeToLog(logPath: logPath, message: "HELPER_ERROR: \(msg)")
            reply(-2, msg)
            return
        }

        guard validateWorkingDirectory(workingDirectory) else {
            let msg = "Répertoire de travail invalide : \(workingDirectory)"
            writeToLog(logPath: logPath, message: "HELPER_ERROR: \(msg)")
            reply(-3, msg)
            return
        }

        // Valider le chemin du log (doit être dans /tmp, pas de traversal)
        guard !logPath.contains(".."),
              URL(fileURLWithPath: logPath).standardizedFileURL.path.hasPrefix("/tmp/") else {
            reply(-4, "Chemin de log invalide : \(logPath)")
            return
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: toolPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = buildEnvironment(forToolAt: toolPath)

        // Écrire la sortie dans le fichier log en temps réel
        // en convertissant \r en \n pour le parsing
        let logHandle = FileHandle(forWritingAtPath: logPath)
            ?? { FileManager.default.createFile(atPath: logPath, contents: nil); return FileHandle(forWritingAtPath: logPath)! }()

        pipe.fileHandleForReading.readabilityHandler = { @Sendable handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            // Convertir \r en \n
            if var str = String(data: data, encoding: .utf8) {
                str = str.replacingOccurrences(of: "\r", with: "\n")
                if let converted = str.data(using: .utf8) {
                    logHandle.write(converted)
                }
            }
        }

        do {
            try process.run()
            currentProcess.withLock { $0 = process }
            process.waitUntilExit()
            currentProcess.withLock { $0 = nil }

            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain remaining data
            let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
            if !remaining.isEmpty {
                if var str = String(data: remaining, encoding: .utf8) {
                    str = str.replacingOccurrences(of: "\r", with: "\n")
                    if let converted = str.data(using: .utf8) {
                        logHandle.write(converted)
                    }
                }
            }
            logHandle.closeFile()

            reply(process.terminationStatus, "")
        } catch {
            currentProcess.withLock { $0 = nil }
            pipe.fileHandleForReading.readabilityHandler = nil
            logHandle.closeFile()
            let msg = "Impossible de lancer l'outil : \(error.localizedDescription)"
            writeToLog(logPath: logPath, message: "HELPER_ERROR: \(msg)")
            reply(-5, msg)
        }
    }

    func cancelCurrentProcess(reply: @escaping (Bool) -> Void) {
        let process = currentProcess.withLock { $0 }
        if let process, process.isRunning {
            process.interrupt()
            reply(true)
        } else {
            reply(false)
        }
    }

    func shutdown() {
        // Terminate any running process first
        let process = currentProcess.withLock { $0 }
        if let process, process.isRunning {
            process.terminate()
        }
        // exit(0) = successful exit → launchd won't restart (KeepAlive SuccessfulExit: false)
        DispatchQueue.main.async {
            exit(0)
        }
    }

    // MARK: - Environment

    private func buildEnvironment(forToolAt toolPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let frameworksDir = frameworksDirectory(forToolAt: toolPath) {
            env["DYLD_LIBRARY_PATH"] = frameworksDir
        }
        return env
    }

    private func frameworksDirectory(forToolAt path: String) -> String? {
        // All bundled tools are in .app/Contents/Frameworks/<toolname>
        guard path.contains("/Contents/Frameworks/") else { return nil }
        return (path as NSString).deletingLastPathComponent
    }

    // MARK: - Log Helper

    private func writeToLog(logPath: String, message: String) {
        guard !logPath.contains(".."),
              URL(fileURLWithPath: logPath).standardizedFileURL.path.hasPrefix("/tmp/") else { return }
        let handle = FileHandle(forWritingAtPath: logPath)
            ?? { FileManager.default.createFile(atPath: logPath, contents: nil); return FileHandle(forWritingAtPath: logPath) }()
        if let handle, let data = (message + "\n").data(using: .utf8) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        }
    }

    // MARK: - Validation

    /// Validates that the tool path points to a bundled executable or an allowed system tool.
    private func validateToolPath(_ path: String) -> Bool {
        // Check allowed system tools (exact path match)
        if BurnManHelperConstants.allowedSystemToolPaths.contains(path) {
            return FileManager.default.isExecutableFile(atPath: path)
        }

        let toolName = (path as NSString).lastPathComponent

        // Must be a known bundled tool
        guard BurnManHelperConstants.allowedToolNames.contains(toolName) else {
            #if DEBUG
            // Accept DerivedData paths during development
            if path.contains("DerivedData"), BurnManHelperConstants.allowedToolNames.contains(toolName) {
                return FileManager.default.isExecutableFile(atPath: path)
            }
            #endif
            return false
        }

        // Must be inside BurnMan.app/Contents/Frameworks/
        guard path.contains("BurnMan.app"), path.contains("/Contents/Frameworks/") else {
            #if DEBUG
            if path.contains("DerivedData") {
                return FileManager.default.isExecutableFile(atPath: path)
            }
            #endif
            return false
        }

        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Validates that the working directory is valid.
    private func validateWorkingDirectory(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("..") else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Validates arguments based on the tool being invoked.
    private func validateArguments(_ args: [String], toolPath: String) -> Bool {
        let toolName = (toolPath as NSString).lastPathComponent

        // Check for shell injection characters in all arguments
        let forbidden: [Character] = ["|", ";", "&", "`", "$", ">", "<", "\n", "\r"]
        for arg in args {
            if arg.contains(where: { forbidden.contains($0) }) {
                return false
            }
        }

        // Tool-specific validation
        switch toolName {
        case "cdrdao":
            guard let first = args.first,
                  BurnManHelperConstants.cdrdaoCommands.contains(first) else {
                return false
            }

        case "growisofs":
            // growisofs args start with -Z or -M (device path)
            guard let first = args.first,
                  first.hasPrefix("-Z") || first.hasPrefix("-M") || first == "-dry-run" else {
                return false
            }

        case "dvd+rw-format":
            // First arg is the device path, rest are options
            guard !args.isEmpty else { return false }

        case "dvd+rw-mediainfo", "dvd+rw-booktype":
            guard !args.isEmpty else { return false }

        case "dd":
            // dd args must match allowed prefixes (if=/dev/disk*, of=, bs=, etc.)
            guard !args.isEmpty else { return false }
            for arg in args {
                let matchesPrefix = BurnManHelperConstants.ddAllowedPrefixes.contains { arg.hasPrefix($0) }
                guard matchesPrefix else { return false }
            }
            // Must have an if= arg pointing to /dev/disk
            guard args.contains(where: { $0.hasPrefix("if=/dev/disk") }) else { return false }

        default:
            return false
        }

        return true
    }
}

// MARK: - Main

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: BurnManHelperConstants.machServiceName)
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
