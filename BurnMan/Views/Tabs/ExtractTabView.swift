import SwiftUI

enum ExtractSubTab: String, CaseIterable, Identifiable {
    case music = "Music"
    case video = "Video"

    var id: String { rawValue }
}

struct ExtractTabView: View {
    @State private var selectedSubTab: ExtractSubTab = .music

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedSubTab) {
                ForEach(ExtractSubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedSubTab {
                    case .music:
                        ExtractMusicSection()
                    case .video:
                        ExtractVideoSection()
                    }
                }
                .padding(24)
            }
        }
    }
}
