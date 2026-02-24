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

// MARK: - Helper Tool (exécute cdrdao en root)

class HelperTool: NSObject, BurnManHelperProtocol {

    private let currentProcess = Mutex<Process?>(nil)

    func ping(reply: @escaping (String) -> Void) {
        reply(BurnManHelperConstants.helperVersion)
    }

    func runCdrdao(
        cdrdaoPath: String,
        arguments: [String],
        workingDirectory: String,
        reply: @escaping (String, Int32) -> Void
    ) {
        guard validateCdrdaoPath(cdrdaoPath) else {
            reply("Chemin cdrdao non autorisé : \(cdrdaoPath)", -1)
            return
        }

        guard validateArguments(arguments) else {
            reply("Arguments invalides ou caractères interdits", -2)
            return
        }

        guard validateWorkingDirectory(workingDirectory) else {
            reply("Répertoire de travail invalide : \(workingDirectory)", -3)
            return
        }

        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: cdrdaoPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = buildEnvironment(forCdrdaoAt: cdrdaoPath)

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
            reply("Impossible de lancer cdrdao : \(error.localizedDescription)", -5)
        }
    }

    func runCdrdaoWithProgress(
        cdrdaoPath: String,
        arguments: [String],
        workingDirectory: String,
        logPath: String,
        reply: @escaping (Int32, String) -> Void
    ) {
        guard validateCdrdaoPath(cdrdaoPath) else {
            let msg = "Chemin cdrdao non autorisé : \(cdrdaoPath)"
            reply(-1, msg)
            return
        }

        guard validateArguments(arguments) else {
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

        process.executableURL = URL(fileURLWithPath: cdrdaoPath)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = buildEnvironment(forCdrdaoAt: cdrdaoPath)

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
            let msg = "Impossible de lancer cdrdao : \(error.localizedDescription)"
            writeToLog(logPath: logPath, message: "HELPER_ERROR: \(msg)")
            reply(-5, msg)
        }
    }

    func cancelCdrdao(reply: @escaping (Bool) -> Void) {
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

    private func buildEnvironment(forCdrdaoAt cdrdaoPath: String) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        if let frameworksDir = frameworksDirectory(forCdrdaoAt: cdrdaoPath) {
            env["DYLD_LIBRARY_PATH"] = frameworksDir
        }
        return env
    }

    private func frameworksDirectory(forCdrdaoAt path: String) -> String? {
        let frameworksSuffix = "/Contents/Frameworks/cdrdao"
        guard path.hasSuffix(frameworksSuffix) else { return nil }
        return String(path.dropLast("/cdrdao".count))
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

    /// Vérifie que le chemin pointe bien vers cdrdao bundled dans l'app
    private func validateCdrdaoPath(_ path: String) -> Bool {
        guard path.hasSuffix("/Contents/Frameworks/cdrdao"),
              path.contains("BurnMan.app") else {
            #if DEBUG
            // Accept DerivedData paths during development
            if path.contains("DerivedData"), path.hasSuffix("/cdrdao") {
                return FileManager.default.isExecutableFile(atPath: path)
            }
            #endif
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    /// Vérifie que le répertoire de travail est valide
    private func validateWorkingDirectory(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("..") else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Vérifie que les arguments sont valides (pas d'injection)
    private func validateArguments(_ args: [String]) -> Bool {
        let allowedCommands: Set<String> = [
            "write", "simulate", "copy", "read-toc", "read-cd",
            "read-test", "show-toc", "scanbus", "disk-info", "blank", "unlock"
        ]
        guard let first = args.first, allowedCommands.contains(first) else {
            return false
        }

        let forbidden: [Character] = ["|", ";", "&", "`", "$", ">", "<", "\n", "\r"]
        for arg in args {
            if arg.contains(where: { forbidden.contains($0) }) {
                return false
            }
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
