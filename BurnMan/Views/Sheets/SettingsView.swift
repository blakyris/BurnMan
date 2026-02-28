import SwiftUI

struct SettingsView: View {
    @AppStorage("defaultSpeed") private var defaultSpeed = 8
    @AppStorage("defaultRaw") private var defaultRaw = false
    @AppStorage("defaultSwap") private var defaultSwap = false
    @AppStorage("defaultEject") private var defaultEject = true


    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                Form {
                    Section("Default Burn Settings") {
                        Picker("Speed", selection: $defaultSpeed) {
                            ForEach(BurnSettings.availableSpeeds, id: \.self) { speed in
                                Text("\(speed)x").tag(speed)
                            }
                        }

                        Toggle("Mode raw (PS1)", isOn: $defaultRaw)
                        Toggle("Swap audio", isOn: $defaultSwap)
                        Toggle("Eject after burn", isOn: $defaultEject)
                    }

                    Section("cdrdao") {
                        HStack {
                            Text("Path")
                            Spacer()
                            Text(ToolPaths.cdrdao)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Source")
                            Spacer()
                            Text("Bundled with app")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .frame(minWidth: 400, idealWidth: 450)
    }

}
