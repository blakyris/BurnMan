import SwiftUI

struct AudioCapacityView: View {
    @Environment(AudioCDManager.self) private var audioCDManager

    var body: some View {
        let totalMin = Int(audioCDManager.totalDurationSeconds) / 60
        let totalSec = Int(audioCDManager.totalDurationSeconds) % 60

        CapacityGaugeView(
            fraction: audioCDManager.capacityFraction,
            usedLabel: "\(totalMin):\(String(format: "%02d", totalSec))",
            totalLabel: "\(audioCDManager.settings.cdType.maxSeconds / 60):00",
            itemCount: audioCDManager.tracks.count,
            overCapacityMessage: audioCDManager.isOverCapacity ? "Duration exceeds CD capacity" : nil
        ) {
            if !audioCDManager.tracksNeedingConversion.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(audioCDManager.tracksNeedingConversion.count) to convert")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
