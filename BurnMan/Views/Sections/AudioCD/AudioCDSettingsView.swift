import SwiftUI

struct AudioCDSettingsView: View {
    @Environment(AudioCDManager.self) private var audioCDManager

    var body: some View {
        @Bindable var audioCDManager = audioCDManager

        SectionContainer(title: "Options", systemImage: "gearshape") {
            VStack(spacing: 16) {
                SettingRow(
                    title: "Speed",
                    systemImage: "speedometer",
                    description: "Lower speeds reduce errors and improve burn quality."
                ) {
                    Picker("", selection: $audioCDManager.settings.speed) {
                        ForEach(AudioCDSettings.availableSpeeds, id: \.self) { speed in
                            Text("\(speed)x").tag(speed)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "CD Type",
                    systemImage: "opticaldisc",
                    description: "Choose blank disc type: 80 min or 74 min."
                ) {
                    Picker("", selection: $audioCDManager.settings.cdType) {
                        ForEach(CDType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                SettingRow(
                    title: "Eject after burning",
                    systemImage: "eject",
                    description: "Automatically eject disc when burning is complete."
                ) {
                    Toggle("", isOn: $audioCDManager.settings.eject)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }

                SettingRow(
                    title: "Overburn",
                    systemImage: "exclamationmark.triangle",
                    description: "Burn beyond the rated disc capacity. Not supported by all drives."
                ) {
                    Toggle("", isOn: $audioCDManager.settings.overburn)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .disabled(audioCDManager.isRunning)
        }
    }
}
