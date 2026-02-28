import SwiftUI

enum ToolsSubTab: String, CaseIterable, Identifiable {
    case erase = "Erase"
    case metadata = "Metadata"

    var id: String { rawValue }
}

struct ToolsTabView: View {
    @State private var selectedSubTab: ToolsSubTab = .erase

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tool", selection: $selectedSubTab) {
                ForEach(ToolsSubTab.allCases) { tab in
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
                    case .erase:
                        EraseDiscSection()
                    case .metadata:
                        MetadataEditorSection()
                    }
                }
                .padding(24)
            }
        }
    }
}
