import SwiftUI

// MARK: - App Tab

enum AppTab: String, CaseIterable, Identifiable {
    case burn, copy, extract, convert, tools
    var id: String { rawValue }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(ActiveTaskContext.self) private var taskContext
    @Environment(DeviceManager.self) private var deviceManager

    // Managers for unsaved-work detection
    @Environment(AudioCDManager.self) private var audioCDManager
    @Environment(DataDiscManager.self) private var dataDiscManager
    @Environment(VideoDiscManager.self) private var videoDiscManager
    @Environment(DiskImageManager.self) private var diskImageManager
    @Environment(CopyDiscManager.self) private var copyDiscManager
    @Environment(ExtractAudioManager.self) private var extractAudioManager
    @Environment(ExtractVideoManager.self) private var extractVideoManager
    @Environment(MediaPlayerService.self) private var mediaPlayerService

    @State private var selectedTab: AppTab = .burn
    @State private var pendingTab: AppTab?
    @State private var showNavigationAlert = false

    private var hasUnsavedWork: Bool {
        audioCDManager.hasContent
            || dataDiscManager.hasContent
            || videoDiscManager.hasContent
            || diskImageManager.hasContent
            || copyDiscManager.hasContent
            || extractAudioManager.hasContent
            || extractVideoManager.hasContent
            || mediaPlayerService.playingTrackID != nil
    }

    var body: some View {
        mainContent
            .task {
                await deviceManager.scanDevices()
            }
            .modifier(FocusedValuesModifier(taskContext: taskContext, deviceManager: deviceManager))
            .onChange(of: selectedTab) { oldValue, newValue in
                if hasUnsavedWork && pendingTab == nil {
                    pendingTab = newValue
                    selectedTab = oldValue
                    showNavigationAlert = true
                }
            }
            .alert("Leave this view?", isPresented: $showNavigationAlert) {
                Button("Cancel", role: .cancel) {
                    pendingTab = nil
                }
                Button("Leave", role: .destructive) {
                    resetAll()
                    if let tab = pendingTab {
                        selectedTab = tab
                        pendingTab = nil
                    }
                }
            } message: {
                Text("Content has been added. Leaving this view will discard all current data.")
            }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            TabView(selection: $selectedTab) {
                Tab("Burn", systemImage: "flame", value: AppTab.burn) {
                    BurnTabView()
                }
                Tab("Copy", systemImage: "doc.on.doc", value: AppTab.copy) {
                    CopyTabView()
                }
                Tab("Extract", systemImage: "arrow.up.doc", value: AppTab.extract) {
                    ExtractTabView()
                }
                Tab("Convert", systemImage: "arrow.triangle.2.circlepath", value: AppTab.convert) {
                    ConvertTabView()
                }
                Tab("Tools", systemImage: "wrench.and.screwdriver", value: AppTab.tools) {
                    ToolsTabView()
                }
            }
            .tabViewStyle(.tabBarOnly)

            BottomToolbar()
        }
    }

    private func resetAll() {
        audioCDManager.reset()
        dataDiscManager.reset()
        videoDiscManager.reset()
        diskImageManager.reset()
        copyDiscManager.reset()
        extractAudioManager.reset()
        extractVideoManager.reset()
        mediaPlayerService.stop()
    }
}
// Bridge ActiveTaskContext → FocusedValues for menu commands
private struct FocusedValuesModifier: ViewModifier {
    let taskContext: ActiveTaskContext
    let deviceManager: DeviceManager

    func body(content: Content) -> some View {
        content
            .focusedSceneValue(\.burnAction, taskContext.onExecute)
            .focusedSceneValue(\.simulateAction, taskContext.onSimulate)
            .focusedSceneValue(\.cancelAction, taskContext.onCancel)
            .focusedSceneValue(\.addFilesAction, taskContext.onAddFiles)
            .focusedSceneValue(\.openCueAction, taskContext.onOpenCue)
            .focusedSceneValue(\.saveCueAction, taskContext.onSaveCue)
            .focusedSceneValue(\.canBurn, taskContext.canExecute)
            .focusedSceneValue(\.isRunning, taskContext.isRunning)
            .focusedSceneValue(\.showLog, Binding(
                get: { taskContext.showLog },
                set: { taskContext.showLog = $0 }
            ))
            .focusedSceneValue(\.refreshDevicesAction, {
                Task { await deviceManager.scanDevices() }
            })
    }
}

