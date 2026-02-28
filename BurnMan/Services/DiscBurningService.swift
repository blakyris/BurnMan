import DiscRecording
import Foundation
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

// MARK: - Types

struct BurnOptions: Sendable {
    var speed: Int?
    var simulate: Bool = false
    var eject: Bool = true
    var appendable: Bool = false
    var verify: Bool = false
}

struct CdrdaoOptions: Sendable {
    var speed: Int?
    var simulate: Bool = false
    var eject: Bool = true
    var overburn: Bool = false
    var reload: Bool = false
    var onTheFly: Bool = false
    var rawMode: Bool = false
    var swapAudio: Bool = false
}

struct BurnResult: Sendable {
    var success: Bool
    var errorMessage: String
}

struct EraseResult: Sendable {
    var success: Bool
    var errorMessage: String
}

enum BurnState: Sendable {
    case preparing
    case writing
    case verifying
    case finishing
    case completed
    case failed
}

struct BurnStatus: Sendable {
    var state: BurnState = .preparing
    var percentComplete: Double = 0
    var currentSpeed: Double = 0
}

enum EraseState: Sendable {
    case erasing
    case completed
    case failed
}

struct EraseStatus: Sendable {
    var state: EraseState = .erasing
    var percentComplete: Double = 0
}

enum BlankMode: String, CaseIterable, Identifiable {
    case full
    case minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .full:    return "Full"
        case .minimal: return "Quick"
        }
    }
}

// MARK: - ISO Track Producer

/// Feeds ISO file data to DRBurn via the DRTrackDataProduction protocol.
private class ISOTrackProducer: NSObject, DRTrackDataProduction {
    private let isoPath: String
    private let isoSize: UInt64
    private var fileHandle: FileHandle?

    init(isoPath: String, isoSize: UInt64) {
        self.isoPath = isoPath
        self.isoSize = isoSize
    }

    // MARK: - Required

    func estimateLength(of track: DRTrack?) -> UInt64 {
        isoSize
    }

    func prepare(_ track: DRTrack?, for burn: DRBurn?, toMedia mediaInfo: [AnyHashable: Any]?) -> Bool {
        fileHandle = FileHandle(forReadingAtPath: isoPath)
        return fileHandle != nil
    }

    func cleanupTrack(afterBurn track: DRTrack?) {
        fileHandle?.closeFile()
        fileHandle = nil
    }

    func producePreGap(for track: DRTrack?, intoBuffer buffer: UnsafeMutablePointer<CChar>?, length: UInt32, atAddress address: UInt64, blockSize: UInt32, ioFlags flags: UnsafeMutablePointer<UInt32>?) -> UInt32 {
        guard let buffer else { return 0 }
        memset(buffer, 0, Int(length))
        return length
    }

    func produceData(for track: DRTrack?, intoBuffer buffer: UnsafeMutablePointer<CChar>?, length: UInt32, atAddress address: UInt64, blockSize: UInt32, ioFlags flags: UnsafeMutablePointer<UInt32>?) -> UInt32 {
        guard let handle = fileHandle, let buffer else { return 0 }
        let data = handle.readData(ofLength: Int(length))
        guard !data.isEmpty else { return 0 }
        data.withUnsafeBytes { ptr in
            if let base = ptr.baseAddress {
                memcpy(buffer, base, data.count)
            }
        }
        return UInt32(data.count)
    }

    // MARK: - Verification

    func prepareTrack(forVerification track: DRTrack?) -> Bool {
        fileHandle?.seek(toFileOffset: 0)
        return true
    }

    func verifyPreGap(for track: DRTrack?, inBuffer buffer: UnsafePointer<CChar>?, length: UInt32, atAddress address: UInt64, blockSize: UInt32, ioFlags flags: UnsafeMutablePointer<UInt32>?) -> Bool {
        true
    }

    func verifyData(for track: DRTrack?, inBuffer buffer: UnsafePointer<CChar>?, length: UInt32, atAddress address: UInt64, blockSize: UInt32, ioFlags flags: UnsafeMutablePointer<UInt32>?) -> Bool {
        guard let handle = fileHandle, let buffer else { return false }
        let expected = handle.readData(ofLength: Int(length))
        guard expected.count == length else { return false }
        return expected.withUnsafeBytes { ptr in
            memcmp(buffer, ptr.baseAddress!, Int(length)) == 0
        }
    }

    func cleanupTrack(afterVerification track: DRTrack?) -> Bool {
        fileHandle?.closeFile()
        fileHandle = nil
        return true
    }
}

// MARK: - Disc Burning Service

/// Unified burning service with three backends:
/// 1. DiscRecording (Apple framework, no root) — ISO burn, erase
/// 2. cdrdao (root via HelperClient) — Audio CD, raw images, copy, read
/// 3. dvd+rw-booktype (root via HelperClient) — DVD booktype change
class DiscBurningService: NSObject, @unchecked Sendable {
    let helperClient: HelperClient

    /// Called on status changes during burn (DiscRecording).
    var onBurnStatusChanged: (@Sendable (BurnStatus) -> Void)?

    /// Called on status changes during erase (DiscRecording).
    var onEraseStatusChanged: (@Sendable (EraseStatus) -> Void)?

    private let burnLock = NSLock()
    private nonisolated(unsafe) var currentBurn: DRBurn?
    private nonisolated(unsafe) var burnContinuation: OnceContinuation<BurnResult>?
    private let eraseLock = NSLock()
    private nonisolated(unsafe) var currentErase: DRErase?
    private nonisolated(unsafe) var eraseContinuation: OnceContinuation<EraseResult>?

    init(helperClient: HelperClient) {
        self.helperClient = helperClient
    }

    // Synchronous helpers — NSLock.lock() is unavailable from async contexts.
    private func setCurrentBurn(_ burn: DRBurn?) {
        burnLock.lock(); currentBurn = burn; burnLock.unlock()
    }

    private func setCurrentErase(_ erase: DRErase?) {
        eraseLock.lock(); currentErase = erase; eraseLock.unlock()
    }

    // MARK: - DiscRecording: Burn ISO

    /// Burns an ISO image to a disc using Apple's DiscRecording framework.
    /// No root required.
    func burnISO(
        isoPath: String,
        device: DRDevice,
        options: BurnOptions
    ) async -> BurnResult {
        // Verify ISO file exists
        guard FileManager.default.fileExists(atPath: isoPath) else {
            return BurnResult(success: false, errorMessage: "ISO file not found: \(isoPath)")
        }

        // Get file size for track length
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: isoPath),
              let fileSize = attrs[.size] as? UInt64 else {
            return BurnResult(success: false, errorMessage: "Unable to read ISO file size")
        }

        // Check device has media
        guard let deviceStatus = device.status(),
              let mediaState = deviceStatus[DRDeviceMediaStateKey] as? String,
              mediaState == DRDeviceMediaStateMediaPresent else {
            return BurnResult(success: false, errorMessage: "No disc inserted in the drive")
        }

        let blockSize: UInt32 = 2048
        let blockCount = UInt32(fileSize / UInt64(blockSize))

        // Create track producer
        let producer = ISOTrackProducer(isoPath: isoPath, isoSize: fileSize)

        // Create track
        guard let track = DRTrack(producer: producer) else {
            return BurnResult(success: false, errorMessage: "Unable to create burn track")
        }
        let properties: [String: Any] = [
            DRTrackLengthKey: NSNumber(value: blockCount),
            DRBlockSizeKey: NSNumber(value: blockSize),
            DRBlockTypeKey: NSNumber(value: Int(kDRBlockTypeMode1Data)),
            DRDataFormKey: NSNumber(value: Int(kDRDataFormMode1Data)),
            DRSessionFormatKey: NSNumber(value: 0),
            DRTrackModeKey: NSNumber(value: Int(kDRTrackMode1Data)),
            DRVerificationTypeKey: options.verify
                ? DRVerificationTypeProduceAgain
                : DRVerificationTypeNone,
        ]
        track.setProperties(properties)

        // Create burn
        guard let burn = DRBurn(device: device) else {
            return BurnResult(success: false, errorMessage: "Unable to initialize burn for this drive")
        }

        var burnProperties: [String: Any] = [:]
        if let speed = options.speed {
            burnProperties[DRBurnRequestedSpeedKey] = NSNumber(value: Float(speed) * kDRDeviceBurnSpeedCD1x)
        }
        if options.simulate {
            burnProperties[DRBurnTestingKey] = NSNumber(value: true)
        }
        if !options.eject {
            burnProperties[DRBurnCompletionActionKey] = DRBurnCompletionActionEject // eject is default; no-eject not directly supported
        }
        if options.appendable {
            burnProperties[DRBurnAppendableKey] = NSNumber(value: true)
        }
        if !burnProperties.isEmpty {
            burn.setProperties(burnProperties)
        }

        setCurrentBurn(burn)

        // Observe notifications
        return await withCheckedContinuation { continuation in
            let onceCont = OnceContinuation(continuation)
            self.burnContinuation = onceCont

            let center = NotificationCenter.default

            var statusObserver: NSObjectProtocol?
            statusObserver = center.addObserver(
                forName: .DRBurnStatusChanged,
                object: burn,
                queue: .main
            ) { [weak self] notification in
                guard let statusDict = notification.userInfo else { return }

                let stateString = statusDict[DRStatusStateKey] as? String ?? ""
                let percent = statusDict[DRStatusPercentCompleteKey] as? Double ?? 0
                let speed = statusDict[DRStatusCurrentSpeedKey] as? Double ?? 0

                let state: BurnState
                switch stateString {
                case DRStatusStatePreparing: state = .preparing
                case DRStatusStateSessionOpen, DRStatusStateTrackOpen, DRStatusStateTrackWrite:
                    state = .writing
                case DRStatusStateVerifying: state = .verifying
                case DRStatusStateTrackClose, DRStatusStateSessionClose, DRStatusStateFinishing:
                    state = .finishing
                case DRStatusStateDone:
                    state = .completed
                    self?.setCurrentBurn(nil)
                    if let obs = statusObserver { center.removeObserver(obs) }
                    onceCont.resume(returning: BurnResult(success: true, errorMessage: ""))
                    return
                case DRStatusStateFailed:
                    state = .failed
                    let errorStatus = statusDict[DRErrorStatusKey] as? [String: Any]
                    let errorString = errorStatus?[DRErrorStatusErrorStringKey] as? String ?? "Unknown error"
                    self?.setCurrentBurn(nil)
                    if let obs = statusObserver { center.removeObserver(obs) }
                    onceCont.resume(returning: BurnResult(success: false, errorMessage: errorString))
                    return
                default: state = .preparing
                }

                let status = BurnStatus(state: state, percentComplete: percent * 100, currentSpeed: speed)
                self?.onBurnStatusChanged?(status)
            }

            burn.writeLayout([track])

            // Preparing timeout — if stuck in preparing after 2 min, fail.
            // Only captures onceCont (Sendable); observer cleanup happens
            // when the notification eventually fires (as a no-op resume).
            Task {
                try? await Task.sleep(for: .seconds(120))
                onceCont.resume(returning: BurnResult(
                    success: false,
                    errorMessage: "Drive not responding. Check the disc and try again."
                ))
            }
        }
    }

    // MARK: - DiscRecording: Erase

    /// Erases a rewritable disc using Apple's DiscRecording framework.
    /// No root required. Works for CD-RW, DVD±RW, BD-RE.
    func erase(device: DRDevice, quick: Bool = false) async -> EraseResult {
        // Check device has media
        guard let deviceStatus = device.status(),
              let mediaState = deviceStatus[DRDeviceMediaStateKey] as? String,
              mediaState == DRDeviceMediaStateMediaPresent else {
            return EraseResult(success: false, errorMessage: "No disc inserted in the drive")
        }

        guard let eraseOp = DRErase(device: device) else {
            return EraseResult(success: false, errorMessage: "Unable to initialize erase for this drive")
        }

        var eraseProperties: [String: Any] = [:]
        if quick {
            eraseProperties[DREraseTypeKey] = DREraseTypeQuick
        } else {
            eraseProperties[DREraseTypeKey] = DREraseTypeComplete
        }
        eraseOp.setProperties(eraseProperties)

        setCurrentErase(eraseOp)

        return await withCheckedContinuation { continuation in
            let onceCont = OnceContinuation(continuation)
            self.eraseContinuation = onceCont

            let center = NotificationCenter.default

            var statusObserver: NSObjectProtocol?
            statusObserver = center.addObserver(
                forName: .DREraseStatusChanged,
                object: eraseOp,
                queue: .main
            ) { [weak self] notification in
                guard let statusDict = notification.userInfo else { return }

                let stateString = statusDict[DRStatusStateKey] as? String ?? ""
                let percent = statusDict[DRStatusPercentCompleteKey] as? Double ?? 0

                switch stateString {
                case DRStatusStateDone:
                    self?.setCurrentErase(nil)
                    if let obs = statusObserver { center.removeObserver(obs) }
                    onceCont.resume(returning: EraseResult(success: true, errorMessage: ""))
                    return
                case DRStatusStateFailed:
                    let errorStatus = statusDict[DRErrorStatusKey] as? [String: Any]
                    let errorString = errorStatus?[DRErrorStatusErrorStringKey] as? String ?? "Unknown error"
                    self?.setCurrentErase(nil)
                    if let obs = statusObserver { center.removeObserver(obs) }
                    onceCont.resume(returning: EraseResult(success: false, errorMessage: errorString))
                    return
                default:
                    let status = EraseStatus(state: .erasing, percentComplete: percent * 100)
                    self?.onEraseStatusChanged?(status)
                }
            }

            eraseOp.start()

            // Preparing timeout — if stuck after 2 min, fail.
            // Only captures onceCont (Sendable); observer cleanup happens
            // when the notification eventually fires (as a no-op resume).
            Task {
                try? await Task.sleep(for: .seconds(120))
                onceCont.resume(returning: EraseResult(
                    success: false,
                    errorMessage: "Drive not responding. Check the disc and try again."
                ))
            }
        }
    }

    // MARK: - DiscRecording: Device Discovery

    /// Finds a DRDevice matching a BSD name (e.g. "disk4").
    func findDevice(bsdName: String) -> DRDevice? {
        guard let devices = DRDevice.devices() as? [DRDevice] else { return nil }
        for device in devices {
            // BSD name is in the media info sub-dictionary of status()
            if let status = device.status(),
               let mediaInfo = status[DRDeviceMediaInfoKey] as? [String: Any],
               let bsd = mediaInfo[DRDeviceMediaBSDNameKey] as? String,
               bsd == bsdName {
                return device
            }
        }
        return nil
    }

    /// Returns all available DiscRecording devices.
    func allDevices() -> [DRDevice] {
        (DRDevice.devices() as? [DRDevice]) ?? []
    }

    // MARK: - cdrdao: Write

    /// Burns a TOC/CUE file via cdrdao (requires root via helper).
    func writeCdrdao(
        tocFile: String,
        device: String,
        options: CdrdaoOptions,
        workingDirectory: String,
        logPath: String
    ) async -> (exitCode: Int32, errorMessage: String) {
        var args: [String] = [options.simulate ? "simulate" : "write"]
        args += ["--device", device]
        if let speed = options.speed { args += ["--speed", "\(speed)"] }
        if options.rawMode { args += ["--driver", "generic-mmc-raw"] }
        if options.overburn { args.append("--overburn") }
        if options.eject { args.append("--eject") }
        if options.swapAudio { args.append("--swap") }
        if options.reload { args.append("--reload") }
        if options.onTheFly { args.append("--on-the-fly") }
        args.append(tocFile)

        return await helperClient.runToolWithProgress(
            toolPath: ToolPaths.cdrdao,
            arguments: args,
            workingDirectory: workingDirectory,
            logPath: logPath
        )
    }

    // MARK: - cdrdao: Copy

    /// Copies a disc using cdrdao (disc-to-disc, requires root).
    func copyDisc(
        sourceDevice: String,
        destDevice: String,
        onTheFly: Bool = false
    ) async -> (output: String, exitCode: Int32) {
        var args = ["copy", "--source-device", sourceDevice, "--device", destDevice]
        if onTheFly { args.append("--on-the-fly") }

        return await helperClient.runTool(
            toolPath: ToolPaths.cdrdao,
            arguments: args,
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    // MARK: - cdrdao: Read

    /// Full disc extraction (TOC + audio data).
    func readCD(device: String, outputFile: String) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.cdrdao,
            arguments: ["read-cd", "--device", device, outputFile],
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    /// Reads the TOC and saves it to a file.
    func readTOC(device: String, outputFile: String) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.cdrdao,
            arguments: ["read-toc", "--device", device, outputFile],
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    /// Shows the TOC of a disc.
    func showTOC(device: String) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.cdrdao,
            arguments: ["show-toc", "--device", device],
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    // MARK: - cdrdao: Unlock

    /// Unlocks a drive left in a locked state after an interrupted burn.
    func unlock(device: String) async -> (exitCode: Int32, errorMessage: String) {
        await helperClient.runToolWithProgress(
            toolPath: ToolPaths.cdrdao,
            arguments: ["unlock", "--device", device],
            workingDirectory: FileManager.default.temporaryDirectory.path,
            logPath: HelperLogPath.unlock
        )
    }

    // MARK: - dvd+rw-booktype

    /// Changes the DVD booktype (bitsetting). Requires root.
    func setBooktype(device: String, booktype: String) async -> (output: String, exitCode: Int32) {
        await helperClient.runTool(
            toolPath: ToolPaths.dvdRwBooktype,
            arguments: ["-dvd+r-booktype=\(booktype)", device],
            workingDirectory: FileManager.default.temporaryDirectory.path
        )
    }

    // MARK: - Cancel

    /// Cancels the current DiscRecording burn.
    func cancelBurn() {
        burnLock.lock()
        currentBurn?.abort()
        currentBurn = nil
        burnLock.unlock()
        burnContinuation?.resume(returning: BurnResult(
            success: false, errorMessage: "Cancelled by user"
        ))
    }

    /// Cancels the current DiscRecording erase (best effort — erase may not be cancellable).
    func cancelErase() {
        // DRErase doesn't have an abort method — the operation may continue.
        // We clear our reference to stop tracking status.
        eraseLock.lock()
        currentErase = nil
        eraseLock.unlock()
        eraseContinuation?.resume(returning: EraseResult(
            success: false, errorMessage: "Cancelled by user"
        ))
    }

    /// Cancels the current cdrdao process running via the helper.
    func cancelCdrdao() {
        Task {
            _ = await helperClient.cancelCurrentProcess()
        }
    }
}
