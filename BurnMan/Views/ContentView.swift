import SwiftUI

struct ContentView: View {
    @Environment(ActiveTaskContext.self) private var taskContext
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                Tab("Burn", systemImage: "flame") {
                    BurnTabView()
                }
                Tab("Copy", systemImage: "doc.on.doc") {
                    CopyTabView()
                }
                Tab("Extract", systemImage: "arrow.down.circle") {
                    ExtractTabView()
                }
                Tab("Convert", systemImage: "arrow.2.squarepath") {
                    ConvertTabView()
                }
                Tab("Tools", systemImage: "wrench.and.screwdriver") {
                    ToolsTabView()
                }
            }

            BottomToolbar()
        }
        .task {
            await deviceManager.scanDevices()
        }
        // Bridge ActiveTaskContext → FocusedValues for menu commands
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
