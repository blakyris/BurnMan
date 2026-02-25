import SwiftUI

enum CopySubTab: String, CaseIterable, Identifiable {
    case discToDisc = "Disc to Disc"
    case discImage = "Disc Image"

    var id: String { rawValue }
}

struct CopyTabView: View {
    @State private var selectedSubTab: CopySubTab = .discToDisc

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedSubTab) {
                ForEach(CopySubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedSubTab {
                    case .discToDisc:
                        CopyDiscToDiscSection()
                    case .discImage:
                        CopyDiscImageSection()
                    }
                }
                .padding(24)
            }
        }
    }
}
