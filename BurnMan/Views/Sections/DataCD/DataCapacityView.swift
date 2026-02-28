import SwiftUI

struct DataCapacityView: View {
    @Environment(DataDiscManager.self) private var dataDiscManager

    var body: some View {
        CapacityGaugeView(
            fraction: dataDiscManager.capacityFraction,
            usedLabel: String(format: "%.1f MB", dataDiscManager.totalSizeMB),
            totalLabel: String(format: "%.0f MB", dataDiscManager.settings.cdCapacity.megabytes),
            itemCount: dataDiscManager.files.count,
            overCapacityMessage: dataDiscManager.isOverCapacity ? "Total size exceeds CD capacity" : nil
        )
    }
}
