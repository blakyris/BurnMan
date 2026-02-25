import Foundation

/// Manages disc erasing for CD-RW, DVD±RW, and BD-RE.
@MainActor
@Observable
class EraseDiscManager {
    // MARK: - State

    var state: PipelineState = .idle
    var error: String?
    var blankMode: BlankMode = .full
    var log: [String] = []

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let dvdService: DVDService
    let blurayService: BlurayService

    // MARK: - Private

    private var logPollTask: Task<Void, Never>?
    private var lastLogOffset: UInt64 = 0

    // MARK: - Init

    init(
        compactDiscService: CompactDiscService,
        dvdService: DVDService,
        blurayService: BlurayService
    ) {
        self.compactDiscService = compactDiscService
        self.dvdService = dvdService
        self.blurayService = blurayService
    }

    var isRunning: Bool { state.isActive }

    // MARK: - Erase

    func erase(device: String, mediaType: MediaType) async {
        guard mediaType.isRewritable else {
            fail("Ce type de disque ne peut pas être effacé.")
            return
        }

        state = .erasing
        error = nil
        log = []

        let logPath = "/tmp/burnman_erase_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)
        startLogPolling(logPath: logPath)

        appendLog("Effacement du disque (\(mediaType.displayName))...")

        let exitCode: Int32
        let errorMessage: String

        switch mediaType {
        case .cdRW:
            (exitCode, errorMessage) = await compactDiscService.blank(
                device: device, mode: blankMode, logPath: logPath
            )
        case .dvdPlusRW:
            (exitCode, errorMessage) = await dvdService.format(
                device: device, force: true, logPath: logPath
            )
        case .dvdMinusRW:
            (exitCode, errorMessage) = await dvdService.blankDVDRW(
                device: device, logPath: logPath
            )
        case .bdRE:
            (exitCode, errorMessage) = await blurayService.format(
                device: device, logPath: logPath
            )
        default:
            fail("Type de disque non supporté pour l'effacement.")
            stopLogPolling(logPath: logPath)
            return
        }

        stopLogPolling(logPath: logPath)

        if exitCode == 0 {
            appendLog("Effacement terminé.")
            state = .finished
        } else {
            fail(errorMessage.isEmpty ? "Erreur d'effacement (code \(exitCode))" : errorMessage)
        }
    }

    func cancel() {
        Task { @MainActor in
            _ = await compactDiscService.cancel()
        }
        state = .failed
        error = "Annulé par l'utilisateur"
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
        appendLog("Erreur : \(message)")
    }

    func appendLog(_ message: String) {
        log.append(message)
    }

    // MARK: - Log Polling

    private func startLogPolling(logPath: String) {
        lastLogOffset = 0
        logPollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                readNewLogLines(logPath: logPath)
            }
        }
    }

    private func stopLogPolling(logPath: String) {
        logPollTask?.cancel()
        logPollTask = nil
        readNewLogLines(logPath: logPath)
    }

    private func readNewLogLines(logPath: String) {
        guard let handle = FileHandle(forReadingAtPath: logPath) else { return }
        defer { handle.closeFile() }

        handle.seek(toFileOffset: lastLogOffset)
        let data = handle.readDataToEndOfFile()
        lastLogOffset = handle.offsetInFile

        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        for line in lines {
            appendLog(line)
        }
    }
}
