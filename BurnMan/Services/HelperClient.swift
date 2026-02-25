import Foundation
import Observation
import ServiceManagement
import Synchronization

/// A thread-safe wrapper that ensures a continuation is resumed exactly once.
private final class OnceContinuation<T>: Sendable where T: Sendable {
    private let state: Mutex<(continuation: CheckedContinuation<T, Never>?, resumed: Bool)>

    init(_ continuation: CheckedContinuation<T, Never>) {
        state = Mutex((continuation, false))
    }

    func resume(returning value: T) {
        let cont: CheckedContinuation<T, Never>? = state.withLock { s in
            guard !s.resumed else { return nil }
            s.resumed = true
            let c = s.continuation
            s.continuation = nil
            return c
        }
        cont?.resume(returning: value)
    }
}

// MARK: - Helper Client

@MainActor
@Observable
class HelperClient {
    var isInstalled = false
    var helperVersion: String?

    private var connection: NSXPCConnection?

    // MARK: - Install Helper

    /// Enregistre le helper comme LaunchDaemon via SMAppService (macOS 13+)
    func installHelper() throws {
        let service = SMAppService.daemon(
            plistName: "org.burnman.helper.plist"
        )

        let status = service.status
        if status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            throw HelperError.requiresApproval
        }

        try service.register()

        // register() peut réussir mais nécessiter l'approbation utilisateur
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
            throw HelperError.requiresApproval
        }

        isInstalled = true
    }

    enum HelperError: LocalizedError {
        case requiresApproval

        var errorDescription: String? {
            switch self {
            case .requiresApproval:
                return "Activez BurnMan dans Réglages Système > Général > Ouverture, puis réessayez."
            }
        }
    }

    /// Désinstalle le helper
    func uninstallHelper() throws {
        let service = SMAppService.daemon(
            plistName: "org.burnman.helper.plist"
        )
        try service.unregister()
        isInstalled = false
    }

    /// Vérifie si le helper est installé
    func checkInstallation() {
        let service = SMAppService.daemon(
            plistName: "org.burnman.helper.plist"
        )
        isInstalled = (service.status == .enabled)
    }

    // MARK: - XPC Connection

    private func getConnection() -> NSXPCConnection {
        if let existing = connection {
            return existing
        }

        let conn = NSXPCConnection(machServiceName: BurnManHelperConstants.machServiceName)
        conn.remoteObjectInterface = NSXPCInterface(with: BurnManHelperProtocol.self)

        conn.invalidationHandler = { @Sendable [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }

        conn.interruptionHandler = { @Sendable [weak self] in
            Task { @MainActor in
                self?.connection = nil
            }
        }

        conn.resume()
        self.connection = conn
        return conn
    }

    /// Returns a proxy whose error handler resumes the given safe continuation
    /// with a fallback value, preventing leaked continuations when XPC fails.
    private func getProxy<T: Sendable>(
        safe: OnceContinuation<T>,
        fallback: T
    ) -> BurnManHelperProtocol? {
        let conn = getConnection()
        let proxy = conn.remoteObjectProxyWithErrorHandler { @Sendable error in
            print("XPC error: \(error)")
            safe.resume(returning: fallback)
        } as? BurnManHelperProtocol

        guard proxy != nil else {
            safe.resume(returning: fallback)
            return nil
        }
        return proxy
    }

    // MARK: - Ping

    func ping() async -> String? {
        if let version = await pingOnce() { return version }
        // Connection was stale — reset and retry once
        disconnect()
        return await pingOnce()
    }

    private func pingOnce() async -> String? {
        await withCheckedContinuation { continuation in
            let safe = OnceContinuation(continuation)
            guard let proxy = getProxy(safe: safe, fallback: nil) else { return }
            proxy.ping { @Sendable version in
                safe.resume(returning: version)
            }
        }
    }

    // MARK: - Run Tool

    func runTool(
        toolPath: String,
        arguments: [String],
        workingDirectory: String
    ) async -> (output: String, exitCode: Int32) {
        await withCheckedContinuation { continuation in
            let safe = OnceContinuation(continuation)
            guard let proxy = getProxy(safe: safe, fallback: ("Helper non connecté", -1)) else { return }
            proxy.runTool(toolPath: toolPath, arguments: arguments, workingDirectory: workingDirectory) { @Sendable output, exitCode in
                safe.resume(returning: (output, exitCode))
            }
        }
    }

    /// Lance un outil avec progression via fichier log.
    /// L'app poll le fichier log pour afficher la progression.
    func runToolWithProgress(
        toolPath: String,
        arguments: [String],
        workingDirectory: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        await withCheckedContinuation { continuation in
            let safe = OnceContinuation(continuation)
            guard let proxy = getProxy(safe: safe, fallback: (-1, "Helper non connecté")) else { return }
            proxy.runToolWithProgress(
                toolPath: toolPath,
                arguments: arguments,
                workingDirectory: workingDirectory,
                logPath: logPath
            ) { @Sendable exitCode, errorMessage in
                safe.resume(returning: (exitCode, errorMessage))
            }
        }
    }

    // MARK: - Cancel

    func cancelCurrentProcess() async -> Bool {
        await withCheckedContinuation { continuation in
            let safe = OnceContinuation(continuation)
            guard let proxy = getProxy(safe: safe, fallback: false) else { return }
            proxy.cancelCurrentProcess { @Sendable success in
                safe.resume(returning: success)
            }
        }
    }

    // MARK: - Shutdown

    /// Demande au helper de se terminer proprement, puis ferme la connexion.
    func shutdown() {
        guard let conn = connection else { return }
        let proxy = conn.remoteObjectProxyWithErrorHandler { _ in } as? BurnManHelperProtocol
        proxy?.shutdown()
        disconnect()
    }

    func disconnect() {
        connection?.invalidate()
        connection = nil
    }
}
