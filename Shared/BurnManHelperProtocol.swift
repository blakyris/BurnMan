import Foundation

// MARK: - XPC Protocol
// Protocol partagé entre l'app et le helper privilégié.
// Le helper exécute cdrdao avec les droits root.

@objc protocol BurnManHelperProtocol {
    /// Exécute cdrdao avec les arguments fournis.
    /// Le helper tourne en root, donc pas besoin de sudo.
    /// - Parameters:
    ///   - cdrdaoPath: Chemin absolu vers cdrdao
    ///   - arguments: Arguments de la commande (write, --speed, etc.)
    ///   - reply: Callback avec (sortie stdout+stderr, code de sortie)
    func runCdrdao(
        cdrdaoPath: String,
        arguments: [String],
        workingDirectory: String,
        reply: @escaping (_ output: String, _ exitCode: Int32) -> Void
    )

    /// Exécute cdrdao avec progression en temps réel via un fichier log.
    /// - Parameters:
    ///   - cdrdaoPath: Chemin absolu vers cdrdao
    ///   - arguments: Arguments de la commande
    ///   - workingDirectory: Répertoire de travail (dossier du CUE)
    ///   - logPath: Chemin du fichier log pour la progression temps réel
    ///   - reply: Callback avec le code de sortie
    func runCdrdaoWithProgress(
        cdrdaoPath: String,
        arguments: [String],
        workingDirectory: String,
        logPath: String,
        reply: @escaping (_ exitCode: Int32, _ errorMessage: String) -> Void
    )

    /// Annule le processus cdrdao en cours.
    func cancelCdrdao(reply: @escaping (_ success: Bool) -> Void)

    /// Vérifie que le helper est installé et fonctionnel.
    func ping(reply: @escaping (_ version: String) -> Void)

    /// Demande au helper de se terminer proprement.
    func shutdown()
}

// MARK: - Constants

enum BurnManHelperConstants {
    static let machServiceName = "org.burnman.helper"
    static let helperVersion = "1.1.0"
}
