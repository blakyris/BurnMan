import AppKit
import SwiftUI
import Synchronization

// MARK: - Focused Values

struct FocusedShowLogKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

struct FocusedBurnActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusedSimulateActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusedCancelActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusedAddFilesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusedOpenCueActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusedSaveCueActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

struct FocusedCanBurnKey: FocusedValueKey {
    typealias Value = Bool
}

struct FocusedIsRunningKey: FocusedValueKey {
    typealias Value = Bool
}

struct FocusedRefreshDevicesActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var showLog: Binding<Bool>? {
        get { self[FocusedShowLogKey.self] }
        set { self[FocusedShowLogKey.self] = newValue }
    }
    var burnAction: (() -> Void)? {
        get { self[FocusedBurnActionKey.self] }
        set { self[FocusedBurnActionKey.self] = newValue }
    }
    var simulateAction: (() -> Void)? {
        get { self[FocusedSimulateActionKey.self] }
        set { self[FocusedSimulateActionKey.self] = newValue }
    }
    var cancelAction: (() -> Void)? {
        get { self[FocusedCancelActionKey.self] }
        set { self[FocusedCancelActionKey.self] = newValue }
    }
    var addFilesAction: (() -> Void)? {
        get { self[FocusedAddFilesActionKey.self] }
        set { self[FocusedAddFilesActionKey.self] = newValue }
    }
    var openCueAction: (() -> Void)? {
        get { self[FocusedOpenCueActionKey.self] }
        set { self[FocusedOpenCueActionKey.self] = newValue }
    }
    var saveCueAction: (() -> Void)? {
        get { self[FocusedSaveCueActionKey.self] }
        set { self[FocusedSaveCueActionKey.self] = newValue }
    }
    var canBurn: Bool? {
        get { self[FocusedCanBurnKey.self] }
        set { self[FocusedCanBurnKey.self] = newValue }
    }
    var isRunning: Bool? {
        get { self[FocusedIsRunningKey.self] }
        set { self[FocusedIsRunningKey.self] = newValue }
    }
    var refreshDevicesAction: (() -> Void)? {
        get { self[FocusedRefreshDevicesActionKey.self] }
        set { self[FocusedRefreshDevicesActionKey.self] = newValue }
    }
}

// MARK: - App Commands

struct BurnCommands: Commands {
    @FocusedValue(\.burnAction) var burnAction
    @FocusedValue(\.simulateAction) var simulateAction
    @FocusedValue(\.cancelAction) var cancelAction
    @FocusedValue(\.canBurn) var canBurn
    @FocusedValue(\.isRunning) var isRunning
    @FocusedValue(\.showLog) var showLog
    @FocusedValue(\.addFilesAction) var addFilesAction
    @FocusedValue(\.openCueAction) var openCueAction
    @FocusedValue(\.saveCueAction) var saveCueAction
    @FocusedValue(\.refreshDevicesAction) var refreshDevicesAction

    var body: some Commands {
        // File menu additions
        CommandGroup(after: .newItem) {
            Divider()

            Button("Open CUE File…") {
                openCueAction?()
            }
            .keyboardShortcut("o")
            .disabled(openCueAction == nil)

            Button("Add Audio Files…") {
                addFilesAction?()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(addFilesAction == nil)

            Button("Save CUE…") {
                saveCueAction?()
            }
            .keyboardShortcut("s")
            .disabled(saveCueAction == nil)
        }

        // Burn menu
        CommandMenu("Burn") {
            Button("Burn") {
                burnAction?()
            }
            .keyboardShortcut("b")
            .disabled(burnAction == nil || canBurn != true || isRunning == true)

            Button("Simulate") {
                simulateAction?()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(simulateAction == nil || canBurn != true || isRunning == true)

            Button("Cancel") {
                cancelAction?()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(cancelAction == nil || isRunning != true)

            Divider()

            Button("Refresh Drives") {
                refreshDevicesAction?()
            }
            .keyboardShortcut("r")
            .disabled(refreshDevicesAction == nil)
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Button("Show Log") {
                showLog?.wrappedValue.toggle()
            }
            .keyboardShortcut("l")
            .disabled(showLog == nil)
        }
    }
}

// MARK: - App

@main
struct BurnManApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    // Shared context for bottom toolbar / menu commands
    @State private var activeTaskContext = ActiveTaskContext()

    // Old managers (kept until views are fully migrated)
    @State private var burnManager = BurnManager()
    @State private var deviceManager = DeviceManager()
    @State private var audioCDManager = AudioCDManager()
    @State private var previewPlayer = AudioPreviewPlayer()

    // New architecture: shared services + managers
    @State private var mediaPlayerService = MediaPlayerService()
    @State private var videoDiscManager: VideoDiscManager
    @State private var dataDiscManager: DataDiscManager
    @State private var copyDiscManager: CopyDiscManager
    @State private var diskImageManager: DiskImageManager
    @State private var eraseDiscManager: EraseDiscManager
    @State private var extractAudioManager: ExtractAudioManager
    @State private var extractVideoManager: ExtractVideoManager

    init() {
        // Shared infrastructure
        let helperClient = HelperClient()
        let toolRunner = ToolRunner()

        // Services
        let compactDiscService = CompactDiscService(helperClient: helperClient)
        let dvdService = DVDService(helperClient: helperClient)
        let blurayService = BlurayService(dvdService: dvdService)
        let mediaProbeService = MediaProbeService(toolRunner: toolRunner)
        let mediaConversionService = MediaConversionService(toolRunner: toolRunner)
        let mediaPlayerService = MediaPlayerService()
        let discImageService = DiscImageService(
            helperClient: helperClient,
            toolRunner: toolRunner,
            decryptionService: DecryptionService()
        )
        let decryptionService = discImageService.decryptionService

        // New managers (for new tabs)
        _mediaPlayerService = State(initialValue: mediaPlayerService)
        _videoDiscManager = State(initialValue: VideoDiscManager(
            mediaProbeService: mediaProbeService,
            mediaConversionService: mediaConversionService,
            dvdService: dvdService,
            blurayService: blurayService,
            mediaPlayerService: mediaPlayerService
        ))
        _dataDiscManager = State(initialValue: DataDiscManager(
            compactDiscService: compactDiscService,
            dvdService: dvdService,
            blurayService: blurayService
        ))
        _copyDiscManager = State(initialValue: CopyDiscManager(
            compactDiscService: compactDiscService,
            discImageService: discImageService,
            dvdService: dvdService,
            blurayService: blurayService,
            decryptionService: decryptionService
        ))
        _diskImageManager = State(initialValue: DiskImageManager(
            compactDiscService: compactDiscService,
            discImageService: discImageService,
            decryptionService: decryptionService
        ))
        _eraseDiscManager = State(initialValue: EraseDiscManager(
            compactDiscService: compactDiscService,
            dvdService: dvdService,
            blurayService: blurayService
        ))
        _extractAudioManager = State(initialValue: ExtractAudioManager(
            compactDiscService: compactDiscService,
            mediaConversionService: mediaConversionService
        ))
        _extractVideoManager = State(initialValue: ExtractVideoManager(
            mediaConversionService: mediaConversionService,
            mediaProbeService: mediaProbeService,
            decryptionService: decryptionService
        ))
    }

    var body: some Scene {
        WindowGroup {
            GlassEffectContainer(spacing: 20) {
                ContentView()
                    // Shared context
                    .environment(activeTaskContext)
                    // Old managers (existing views)
                    .environment(burnManager)
                    .environment(deviceManager)
                    .environment(audioCDManager)
                    .environment(previewPlayer)
                    // New managers (new tabs)
                    .environment(videoDiscManager)
                    .environment(dataDiscManager)
                    .environment(mediaPlayerService)
                    .environment(copyDiscManager)
                    .environment(diskImageManager)
                    .environment(eraseDiscManager)
                    .environment(extractAudioManager)
                    .environment(extractVideoManager)
                    .frame(minWidth: 720, minHeight: 520)
                    .onAppear {
                        appDelegate.burnManager = burnManager
                        appDelegate.audioCDManager = audioCDManager
                    }
            }
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
        .commands {
            BurnCommands()
        }

        Settings {
            SettingsView()
                .environment(burnManager)
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var burnManager: BurnManager?
    weak var audioCDManager: AudioCDManager?

    func applicationWillTerminate(_ notification: Notification) {
        ProcessTracker.shared.terminateAll()
        burnManager?.helperClient.shutdown()
        audioCDManager?.helperClient.shutdown()
    }
}

// MARK: - Process Tracker
/// Keeps track of all child processes so they can be terminated on app quit.
final class ProcessTracker: Sendable {
    static let shared = ProcessTracker()

    private let processes = Mutex<[Int32: Process]>([:])

    func register(_ process: Process) {
        processes.withLock { $0[process.processIdentifier] = process }
    }

    func unregister(_ process: Process) {
        processes.withLock { _ = $0.removeValue(forKey: process.processIdentifier) }
    }

    func terminateAll() {
        let snapshot = processes.withLock { $0.values.filter { $0.isRunning } }
        for proc in snapshot {
            proc.terminate()
        }
    }
}
