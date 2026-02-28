import SwiftUI

enum ConvertSubTab: String, CaseIterable, Identifiable {
    case file = "File"
    case audio = "Audio"
    case video = "Video"
    case discImage = "Disc Image"

    var id: String { rawValue }
}

struct ConvertTabView: View {
    @State private var selectedSubTab: ConvertSubTab = .file

    var body: some View {
        VStack(spacing: 0) {
            Picker("Mode", selection: $selectedSubTab) {
                ForEach(ConvertSubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedSubTab {
                    case .file:
                        ConvertFileSection()
                    case .audio:
                        ConvertAudioSection()
                    case .video:
                        ConvertVideoSection()
                    case .discImage:
                        ConvertDiscImageSection()
                    }
                }
                .padding(24)
            }
        }
    }
}
