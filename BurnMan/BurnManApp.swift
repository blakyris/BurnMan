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

            Button("Ouvrir un fichier CUE…") {
                openCueAction?()
            }
            .keyboardShortcut("o")
            .disabled(openCueAction == nil)

            Button("Ajouter des fichiers audio…") {
                addFilesAction?()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .disabled(addFilesAction == nil)

            Button("Enregistrer le CUE…") {
                saveCueAction?()
            }
            .keyboardShortcut("s")
            .disabled(saveCueAction == nil)
        }

        // Burn menu
        CommandMenu("Gravure") {
            Button("Graver") {
                burnAction?()
            }
            .keyboardShortcut("b")
            .disabled(burnAction == nil || canBurn != true || isRunning == true)

            Button("Simuler") {
                simulateAction?()
            }
            .keyboardShortcut("b", modifiers: [.command, .shift])
            .disabled(simulateAction == nil || canBurn != true || isRunning == true)

            Button("Annuler") {
                cancelAction?()
            }
            .keyboardShortcut(".", modifiers: .command)
            .disabled(cancelAction == nil || isRunning != true)

            Divider()

            Button("Actualiser les graveurs") {
                refreshDevicesAction?()
            }
            .keyboardShortcut("r")
            .disabled(refreshDevicesAction == nil)
        }

        // View menu additions
        CommandGroup(after: .toolbar) {
            Button("Afficher le log") {
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
    @State private var burnManager = BurnManager()
    @State private var deviceManager = DeviceManager()
    @State private var audioCDManager = AudioCDManager()
    @State private var previewPlayer = AudioPreviewPlayer()

    var body: some Scene {
        WindowGroup {
            GlassEffectContainer(spacing: 20) {
                ContentView()
                    .environment(burnManager)
                    .environment(deviceManager)
                    .environment(audioCDManager)
                    .environment(previewPlayer)
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
