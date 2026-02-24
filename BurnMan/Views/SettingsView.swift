import SwiftUI

struct SettingsView: View {
    @Environment(BurnManager.self) private var burnManager
    @AppStorage("defaultSpeed") private var defaultSpeed = 8
    @AppStorage("defaultRaw") private var defaultRaw = false
    @AppStorage("defaultSwap") private var defaultSwap = false
    @AppStorage("defaultEject") private var defaultEject = true


    var body: some View {
        TabView {
            Tab("Général", systemImage: "gearshape") {
                Form {
                    Section("Gravure par défaut") {
                        Picker("Vitesse", selection: $defaultSpeed) {
                            ForEach(BurnSettings.availableSpeeds, id: \.self) { speed in
                                Text("\(speed)x").tag(speed)
                            }
                        }

                        Toggle("Mode raw (PS1)", isOn: $defaultRaw)
                        Toggle("Swap audio", isOn: $defaultSwap)
                        Toggle("Éjecter après gravure", isOn: $defaultEject)
                    }

                    Section("cdrdao") {
                        HStack {
                            Text("Chemin")
                            Spacer()
                            Text(CdrdaoConfig.resolvedPath)
                                .font(.system(.body, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        HStack {
                            Text("Source")
                            Spacer()
                            Text("Intégré à l'application")
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
