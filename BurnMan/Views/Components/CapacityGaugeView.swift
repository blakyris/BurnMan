import SwiftUI

struct CapacityGaugeView<ExtraContent: View>: View {
    let fraction: Double
    let usedLabel: String
    let totalLabel: String
    let itemCount: Int
    var overCapacityMessage: String? = nil
    @ViewBuilder let extraContent: () -> ExtraContent

    var body: some View {
        SectionContainer(title: "Capacity", systemImage: "chart.bar") {
            VStack(spacing: 10) {
                ProgressView(
                    value: min(fraction, 1.0),
                    total: 1.0
                )
                .tint(capacityColor)

                HStack {
                    Text(usedLabel)
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.medium)

                    Text("/")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(totalLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(itemCount) \(itemCount == 1 ? "item" : "items")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    extraContent()
                }

                if let message = overCapacityMessage {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var capacityColor: Color {
        if fraction > 1.0 { return .red }
        if fraction > 0.9 { return .orange }
        return .green
    }
}

extension CapacityGaugeView where ExtraContent == EmptyView {
    init(
        fraction: Double,
        usedLabel: String,
        totalLabel: String,
        itemCount: Int,
        overCapacityMessage: String? = nil
    ) {
        self.fraction = fraction
        self.usedLabel = usedLabel
        self.totalLabel = totalLabel
        self.itemCount = itemCount
        self.overCapacityMessage = overCapacityMessage
        self.extraContent = { EmptyView() }
    }
}
