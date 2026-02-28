import SwiftUI

struct DataCDSettingsView: View {
    @Environment(DataDiscManager.self) private var dataDiscManager

    var body: some View {
        @Bindable var dataDiscManager = dataDiscManager

        SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Speed",
                    systemImage: "speedometer",
                    description: "Lower speeds reduce errors and improve burn quality."
                ) {
                    Picker("", selection: $dataDiscManager.settings.speed) {
                        ForEach(DataCDSettings.availableSpeeds, id: \.self) { speed in
                            Text("\(speed)x").tag(speed)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "Disc Capacity",
                    systemImage: "opticaldisc",
                    description: "Choose blank disc type."
                ) {
                    Picker("", selection: $dataDiscManager.settings.cdCapacity) {
                        ForEach(DataCDCapacity.allCases) { capacity in
                            Text(capacity.displayName).tag(capacity)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "Disc Label",
                    systemImage: "textformat",
                    description: "The label that will appear on the disc."
                ) {
                    TextField("", text: $dataDiscManager.discLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)
                }

                SettingRow(
                    title: "Eject after burning",
                    systemImage: "eject",
                    description: "Automatically eject disc when burning is complete."
                ) {
                    Toggle("", isOn: $dataDiscManager.settings.eject)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Overburn",
                    systemImage: "exclamationmark.triangle",
                    description: "Burn beyond the rated disc capacity. Not supported by all drives."
                ) {
                    Toggle("", isOn: $dataDiscManager.settings.overburn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Multi-session",
                    systemImage: "plus.circle",
                    description: "Leave the disc open for additional sessions."
                ) {
                    Toggle("", isOn: $dataDiscManager.settings.multiSession)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .disabled(dataDiscManager.isRunning)
        }
    }
}
