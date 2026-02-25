import Foundation

/// Manages data CD/DVD/BD burning pipeline.
@MainActor
@Observable
class DataDiscManager {
    // MARK: - State

    var files: [DataFile] = []
    var discLabel: String = "DATA_DISC"
    var fileSystem: FileSystemType = .auto
    var targetMedia: TargetMedia = .dvd
    var state: PipelineState = .idle
    var error: String?

    // MARK: - Services

    let compactDiscService: CompactDiscService
    let dvdService: DVDService
    let blurayService: BlurayService

    // MARK: - Private

    private var cancelled = false
    private var tempDirectory: URL?

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

    // MARK: - File Management

    func addFiles(urls: [URL]) {
        for url in urls {
            let size = fileSize(at: url)
            let file = DataFile(
                url: url,
                name: url.lastPathComponent,
                fileSize: size,
                isDirectory: isDirectory(at: url)
            )
            files.append(file)
        }
    }

    func removeFile(at offsets: IndexSet) {
        files.remove(atOffsets: offsets)
    }

    // MARK: - Size Calculation

    var totalSizeBytes: UInt64 {
        files.reduce(0) { $0 + $1.fileSize }
    }

    var totalSizeMB: Double {
        Double(totalSizeBytes) / 1_048_576.0
    }

    // MARK: - Burn Pipeline

    func startBurn(device: String) async {
        cancelled = false
        error = nil
        state = .preparing

        guard !files.isEmpty else {
            fail("Aucun fichier ajouté.")
            return
        }

        state = .burning

        let logPath = "/tmp/burnman_data_\(ProcessInfo.processInfo.processIdentifier).log"
        FileManager.default.createFile(atPath: logPath, contents: nil)

        // Build and burn based on target media
        let exitCode: Int32
        let errorMessage: String

        switch targetMedia {
        case .cd:
            // For CD data, we'd need mkisofs + cdrdao or direct write
            // Simplified: use growisofs even for CD data when possible
            (exitCode, errorMessage) = await dvdService.burn(
                isoPath: files.first!.url.path,
                device: device,
                logPath: logPath
            )

        case .dvd:
            (exitCode, errorMessage) = await dvdService.burn(
                isoPath: files.first!.url.path,
                device: device,
                logPath: logPath
            )

        case .bluray:
            (exitCode, errorMessage) = await blurayService.burn(
                isoPath: files.first!.url.path,
                device: device,
                logPath: logPath
            )
        }

        if exitCode != 0 {
            fail(errorMessage.isEmpty ? "Erreur de gravure (code \(exitCode))" : errorMessage)
            return
        }

        state = .finished
    }

    func cancel() {
        cancelled = true
        Task { @MainActor in
            switch targetMedia {
            case .cd: _ = await compactDiscService.cancel()
            case .dvd: _ = await dvdService.cancel()
            case .bluray: _ = await blurayService.cancel()
            }
        }
        state = .failed
        error = "Annulé par l'utilisateur"
    }

    // MARK: - Private

    private func fail(_ message: String) {
        state = .failed
        error = message
    }

    private func fileSize(at url: URL) -> UInt64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}

// MARK: - Data File Model

struct DataFile: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var name: String
    var fileSize: UInt64
    var isDirectory: Bool

    var fileSizeMB: Double {
        Double(fileSize) / 1_048_576.0
    }

    var icon: String {
        isDirectory ? "folder" : "doc"
    }
}
