import SwiftUI

/// +/- bottom bar used beneath Table views (AudioCD, DataCD).
struct TableBottomBar: View {
    let onAdd: () -> Void
    let onRemove: () -> Void
    var removeDisabled: Bool = true

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)

            Divider()
                .frame(height: 16)

            Button {
                onRemove()
            } label: {
                Image(systemName: "minus")
                    .frame(width: 24, height: 20)
            }
            .buttonStyle(.borderless)
            .disabled(removeDisabled)

            Spacer()
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .background(.bar)
    }
}
