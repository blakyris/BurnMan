import Foundation

// MARK: - XPC Protocol
// Protocol partagé entre l'app et le helper privilégié.
// Le helper exécute des outils CLI bundled (cdrdao, growisofs, etc.) avec les droits root.

@objc protocol BurnManHelperProtocol {
    /// Exécute un outil CLI bundled avec les arguments fournis.
    /// Le helper tourne en root, donc pas besoin de sudo.
    /// - Parameters:
    ///   - toolPath: Chemin absolu vers l'outil (cdrdao, growisofs, etc.)
    ///   - arguments: Arguments de la commande
    ///   - workingDirectory: Répertoire de travail
    ///   - reply: Callback avec (sortie stdout+stderr, code de sortie)
    func runTool(
        toolPath: String,
        arguments: [String],
        workingDirectory: String,
        reply: @escaping (_ output: String, _ exitCode: Int32) -> Void
    )

    /// Exécute un outil CLI bundled avec progression en temps réel via un fichier log.
    /// - Parameters:
    ///   - toolPath: Chemin absolu vers l'outil
    ///   - arguments: Arguments de la commande
    ///   - workingDirectory: Répertoire de travail
    ///   - logPath: Chemin du fichier log pour la progression temps réel
    ///   - reply: Callback avec le code de sortie
    func runToolWithProgress(
        toolPath: String,
        arguments: [String],
        workingDirectory: String,
        logPath: String,
        reply: @escaping (_ exitCode: Int32, _ errorMessage: String) -> Void
    )

    /// Annule le processus en cours.
    func cancelCurrentProcess(reply: @escaping (_ success: Bool) -> Void)

    /// Vérifie que le helper est installé et fonctionnel.
    func ping(reply: @escaping (_ version: String) -> Void)

    /// Demande au helper de se terminer proprement.
    func shutdown()
}

// MARK: - Constants

enum BurnManHelperConstants {
    static let machServiceName = "org.burnman.helper"
    static let helperVersion = "2.1.0"

    /// Tool names allowed to be executed by the helper (bundled tools).
    static let allowedToolNames: Set<String> = [
        "cdrdao", "growisofs", "dvd+rw-format", "dvd+rw-mediainfo", "dvd+rw-booktype",
    ]

    /// System tool paths allowed to be executed by the helper.
    static let allowedSystemToolPaths: Set<String> = [
        "/bin/dd",
    ]

    /// Valid dd argument prefixes.
    static let ddAllowedPrefixes: [String] = [
        "if=/dev/disk", "of=", "bs=", "count=", "status=",
    ]

    /// Valid cdrdao subcommands.
    static let cdrdaoCommands: Set<String> = [
        "write", "simulate", "copy", "read-toc", "read-cd",
        "read-test", "show-toc", "scanbus", "disk-info", "blank", "unlock",
    ]

    /// Valid growisofs option prefixes.
    static let growisofsAllowedPrefixes: [String] = [
        "-Z", "-M", "-speed=", "-dvd-compat", "-overburn",
        "-use-the-force-luke", "-dry-run",
    ]

    /// Valid dvd+rw-format options.
    static let dvdRwFormatOptions: Set<String> = [
        "-force", "-lead-out", "-blank", "-ssa=none",
    ]
}
