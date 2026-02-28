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

    // Shared services
    @State private var deviceManager = DeviceManager()
    @State private var audioCDManager: AudioCDManager
    @State private var diskImageManager: DiskImageManager

    // New architecture: shared services + managers
    @State private var mediaPlayerService = MediaPlayerService()
    @State private var videoDiscManager: VideoDiscManager
    @State private var dataDiscManager: DataDiscManager
    @State private var copyDiscManager: CopyDiscManager
    @State private var eraseDiscManager: EraseDiscManager
    @State private var extractAudioManager: ExtractAudioManager
    @State private var extractVideoManager: ExtractVideoManager

    init() {
        // Shared infrastructure
        let helperClient = HelperClient()

        // New unified services
        let discAuthoringService = DiscAuthoringService()
        let discBurningService = DiscBurningService(helperClient: helperClient)

        // Existing services (not replaced)
        let mediaProbeService = MediaProbeService()
        let mediaConversionService = MediaConversionService()
        let mediaPlayerService = MediaPlayerService()
        let discImageService = DiscImageService(
            helperClient: helperClient,
            decryptionService: DecryptionService()
        )
        let decryptionService = discImageService.decryptionService

        let audioCDManager = AudioCDManager(
            mediaProbeService: mediaProbeService,
            mediaConversionService: mediaConversionService,
            discBurningService: discBurningService
        )

        // Managers
        _mediaPlayerService = State(initialValue: mediaPlayerService)
        _audioCDManager = State(initialValue: audioCDManager)
        _videoDiscManager = State(initialValue: VideoDiscManager(
            mediaProbeService: mediaProbeService,
            mediaConversionService: mediaConversionService,
            discBurningService: discBurningService,
            mediaPlayerService: mediaPlayerService
        ))
        _dataDiscManager = State(initialValue: DataDiscManager(
            discAuthoringService: discAuthoringService,
            discBurningService: discBurningService
        ))
        _copyDiscManager = State(initialValue: CopyDiscManager(
            discBurningService: discBurningService,
            discImageService: discImageService,
            decryptionService: decryptionService
        ))
        _diskImageManager = State(initialValue: DiskImageManager(
            discBurningService: discBurningService,
            discImageService: discImageService,
            decryptionService: decryptionService
        ))
        _eraseDiscManager = State(initialValue: EraseDiscManager(
            discBurningService: discBurningService
        ))
        _extractAudioManager = State(initialValue: ExtractAudioManager(
            discBurningService: discBurningService,
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
                    // Managers
                    .environment(deviceManager)
                    .environment(audioCDManager)
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
                        appDelegate.discBurningService = audioCDManager.discBurningService
                    }
            }
            .focusEffectDisabled()
        }
        .windowStyle(.automatic)
        .defaultSize(width: 800, height: 600)
        .commands {
            BurnCommands()
        }

        Settings {
            SettingsView()
                .focusEffectDisabled()
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var discBurningService: DiscBurningService?

    func applicationWillTerminate(_ notification: Notification) {
        ProcessTracker.shared.terminateAll()
        discBurningService?.helperClient.shutdown()
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
