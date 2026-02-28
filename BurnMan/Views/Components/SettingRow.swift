import SwiftUI

struct SettingRow<Control: View>: View {
    let title: String
    let systemImage: String
    let description: String
    @ViewBuilder let control: Control

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: systemImage)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            control
        }
    }
}
