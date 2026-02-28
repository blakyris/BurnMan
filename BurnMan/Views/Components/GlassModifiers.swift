import SwiftUI

extension View {
    func statusBadge(color: Color) -> some View {
        self
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(color), in: .rect(cornerRadius: 10))
    }

    func trackModeBadge(mode: TrackMode) -> some View {
        let color: Color = mode == .audio ? .green : .blue
        return self
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(color), in: .capsule)
    }

    func successToastStyle() -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .glassEffect(.regular.tint(.green), in: .capsule)
    }

    func dropHighlight(isTargeted: Bool) -> some View {
        self.overlay {
            if isTargeted {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.blue, lineWidth: 2)
            }
        }
    }
}
