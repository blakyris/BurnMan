import SwiftUI

struct DevicePickerView: View {
    @Environment(DeviceManager.self) private var deviceManager

    var body: some View {
        Menu {
            if deviceManager.devices.isEmpty {
                Text("Aucun graveur détecté")
            } else {
                ForEach(deviceManager.devices) { device in
                    Button {
                        deviceManager.selectedDevice = device
                    } label: {
                        HStack {
                            Text(device.displayName)
                            if device.id == deviceManager.selectedDevice?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Divider()

            Button {
                Task { await deviceManager.scanDevices() }
            } label: {
                Label("Actualiser", systemImage: "arrow.clockwise")
            }
        } label: {
            Label {
                Text(deviceManager.selectedDevice?.displayName ?? "Aucun graveur")
            } icon: {
                Image(systemName: deviceManager.selectedDevice != nil ? "opticaldisc.fill" : "opticaldisc")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sélectionner le graveur")
    }
}
