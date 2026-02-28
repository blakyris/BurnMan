import DiscRecording
import Foundation
import Observation

/// Manages data CD/DVD/BD burning pipeline.
@MainActor
@Observable
class DataDiscManager: Loggable {
    // MARK: - State

    var files: [DataFile] = []
    var discLabel: String = "DATA_DISC"
    var fileSystem: FileSystemType = .auto
    var targetMedia: TargetMedia = .dvd
    var state: PipelineState = .idle
    var error: String?

    // CD-specific state
    var settings = DataCDSettings()
    var progress = DataCDProgress()
    var log: [String] = []

    // MARK: - Services

    let discAuthoringService: DiscAuthoringService
    let discBurningService: DiscBurningService

    // MARK: - Private

    private var cancelled = false
    private var elapsedTask: Task<Void, Never>?
    private var startTime: Date?
    private var tempDirectory: URL?

    // MARK: - Init

    init(
        discAuthoringService: DiscAuthoringService,
        discBurningService: DiscBurningService
    ) {
        self.discAuthoringService = discAuthoringService
        self.discBurningService = discBurningService
    }

    var isRunning: Bool {
        state.isActive || progress.phase.isActive
    }

    // MARK: - Content State

    var hasContent: Bool { !files.isEmpty }

    func reset() {
        cancel()
        files = []
        discLabel = "DATA_DISC"
        state = .idle
        error = nil
        log = []
        progress = DataCDProgress()
    }

    // MARK: - File Management

    func addFiles(urls: [URL]) {
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            let size = fileSize(at: url)
            let file = DataFile(
                url: url,
                name: url.lastPathComponent,
                fileSize: size,
                isDirectory: isDirectory(at: url),
                order: files.count + 1
            )
            files.append(file)
        }
        renumberFiles()
    }

    func removeFiles(at offsets: IndexSet) {
        files.remove(atOffsets: offsets)
        renumberFiles()
    }

    func moveFiles(from source: IndexSet, to destination: Int) {
        files.move(fromOffsets: source, toOffset: destination)
        renumberFiles()
    }

    func sortFiles(using comparators: [KeyPathComparator<DataFile>]) {
        files.sort(using: comparators)
        renumberFiles()
    }

    func renumberFiles() {
        for i in files.indices {
            files[i].order = i + 1
        }
    }

    // MARK: - Size Calculation

    var totalSizeBytes: UInt64 {
        files.reduce(0) { $0 + $1.fileSize }
    }

    var totalSizeMB: Double {
        Double(totalSizeBytes) / 1_048_576.0
    }

    var capacityFraction: Double {
        guard settings.cdCapacity.bytes > 0 else { return 0 }
        return Double(totalSizeBytes) / Double(settings.cdCapacity.bytes)
    }

    var isOverCapacity: Bool { capacityFraction > 1.0 }

    var canBurn: Bool {
        !files.isEmpty && (!isOverCapacity || settings.overburn)
    }

    // MARK: - CD Burn Pipeline (mkisofs + DiscRecording)

    func startBurnCD(device: DiscDevice) async {
        guard canBurn else { return }

        cancelled = false
        log = []
        progress = DataCDProgress()
        startTime = Date()
        startElapsedTimer()

        appendLog("Starting Data CD pipeline...")

        // Validate
        progress.phase = .validating
        guard validateCD() else {
            stopTimers()
            return
        }

        // Stage files to temp directory
        guard !cancelled else { return handleCancel() }
        guard stageFilesToTemp() else {
            progress.phase = .failed("Unable to copy files to temporary directory")
            stopTimers()
            return
        }

        // Create ISO with mkisofs
        guard !cancelled else { return handleCancel() }
        progress.phase = .creatingISO
        let isoPath = (tempDirectory ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("\(discLabel).iso").path

        appendLog("Creating ISO via mkisofs...")
        let mkisofsExitCode = await discAuthoringService.createISO(
            sourceDirectory: tempDirectory!.path,
            outputPath: isoPath,
            volumeLabel: discLabel,
            onLine: { [weak self] line in
                self?.parseMkisofsLine(line)
            }
        )

        guard mkisofsExitCode == 0 else {
            progress.phase = .failed("mkisofs error (code \(mkisofsExitCode))")
            stopTimers()
            cleanupTemp()
            return
        }

        guard !cancelled else { return handleCancel() }

        // Burn ISO via DiscRecording (no root!)
        progress.phase = .burning
        progress.isSimulation = settings.simulate
        appendLog("Burning ISO via DiscRecording...")

        guard let drDevice = findDRDevice(for: device) else {
            progress.phase = .failed("Unable to find DiscRecording drive for \(device.displayName)")
            stopTimers()
            cleanupTemp()
            return
        }

        // Set up status callback
        discBurningService.onBurnStatusChanged = { [weak self] status in
            Task { @MainActor in
                self?.progress.burnPercent = status.percentComplete
                if status.currentSpeed > 0 {
                    self?.progress.writeSpeed = String(format: "%.1fx", status.currentSpeed / Double(kDRDeviceBurnSpeedCD1x))
                }
            }
        }

        nonisolated(unsafe) let safeDevice = drDevice
        let burnResult = await discBurningService.burnISO(
            isoPath: isoPath,
            device: safeDevice,
            options: BurnOptions(
                speed: settings.speed,
                simulate: settings.simulate,
                eject: settings.eject,
                appendable: settings.multiSession
            )
        )

        discBurningService.onBurnStatusChanged = nil

        // Cleanup
        if burnResult.success {
            progress.phase = .cleaningUp
            cleanupTemp()
            progress.phase = .completed
            appendLog("Pipeline completed successfully.")
        } else {
            progress.phase = .failed(burnResult.errorMessage)
            appendLog("ERROR: \(burnResult.errorMessage)")
            cleanupTemp()
        }

        stopTimers()
    }

    // MARK: - DVD/BD Burn Pipeline (DiscRecording)

    func startBurn(device: DiscDevice) async {
        cancelled = false
        error = nil
        state = .preparing

        guard !files.isEmpty else {
            fail("No files added.")
            return
        }

        guard let drDevice = findDRDevice(for: device) else {
            fail("Unable to find DiscRecording drive.")
            return
        }

        state = .burning

        nonisolated(unsafe) let safeDevice = drDevice
        let result = await discBurningService.burnISO(
            isoPath: files.first!.url.path,
            device: safeDevice,
            options: BurnOptions(eject: true)
        )

        if result.success {
            state = .finished
        } else {
            fail(result.errorMessage)
        }
    }

    func cancel() {
        cancelled = true
        discAuthoringService.cancel()
        discBurningService.cancelBurn()
        progress.phase = .failed("Cancelled by user")
        stopTimers()
        cleanupTemp()
    }

    // MARK: - Private — CD Pipeline

    private func validateCD() -> Bool {
        if files.isEmpty {
            progress.phase = .failed("No files added")
            return false
        }

        if isOverCapacity && !settings.overburn {
            progress.phase = .failed("Total size exceeds CD capacity")
            return false
        }

        appendLog("Validation OK: \(files.count) file(s), \(String(format: "%.1f", totalSizeMB)) MB")
        return true
    }

    private func parseMkisofsLine(_ line: String) {
        appendLog(line)

        for event in MkisofsOutputParser.parse(line: line) {
            switch event {
            case .progress(let percent):
                progress.isoPercent = percent
            case .extentsWritten(_, let mb):
                appendLog("ISO completed (\(mb) MB)")
            case .error(let msg):
                progress.phase = .failed(msg)
            }
        }
    }

    // MARK: - Device Resolution

    private func findDRDevice(for device: DiscDevice) -> DRDevice? {
        if let bsd = device.bsdName {
            return discBurningService.findDevice(bsdName: bsd)
        }
        // Fallback: return first available device
        return discBurningService.allDevices().first
    }

    // MARK: - Staging

    private func stageFilesToTemp() -> Bool {
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory
            .appendingPathComponent("BurnMan_\(UUID().uuidString)")

        do {
            try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            appendLog("ERROR: unable to create temporary directory: \(error.localizedDescription)")
            return false
        }
        tempDirectory = tempDir

        appendLog("Copying \(files.count) file(s) to temporary directory...")

        for file in files {
            let accessing = file.url.startAccessingSecurityScopedResource()
            defer { if accessing { file.url.stopAccessingSecurityScopedResource() } }

            let dest = tempDir.appendingPathComponent(file.name)
            do {
                try fm.copyItem(at: file.url, to: dest)
            } catch {
                appendLog("ERROR: copying \(file.name): \(error.localizedDescription)")
                cleanupTemp()
                return false
            }
        }

        appendLog("Files copied to \(tempDir.path)")
        return true
    }

    private func cleanupTemp() {
        if let tempDir = tempDirectory {
            try? FileManager.default.removeItem(at: tempDir)
            appendLog("Temporary files deleted.")
        }
        tempDirectory = nil
    }

    // MARK: - Timers

    private func startElapsedTimer() {
        elapsedTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let s = self.startTime else { return }
                self.progress.elapsedSeconds = Int(Date().timeIntervalSince(s))
            }
        }
    }

    private func stopTimers() {
        elapsedTask?.cancel()
        elapsedTask = nil
    }

    // MARK: - Private Helpers

    private func handleCancel() {
        stopTimers()
        cleanupTemp()
    }

    private func fail(_ message: String) {
        state = .failed
        error = message
    }

    // appendLog() provided by Loggable protocol extension

    private func fileSize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }

        if isDir.boolValue {
            return directorySize(at: url)
        }
        return (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    private func directorySize(at url: URL) -> UInt64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [.skipsHiddenFiles]) else { return 0 }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(size)
            }
        }
        return total
    }

    private func isDirectory(at url: URL) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        return isDir.boolValue
    }
}
