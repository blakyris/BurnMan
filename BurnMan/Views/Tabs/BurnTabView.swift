import SwiftUI

struct BurnTabView: View {
    @State private var selectedMedia: TargetMedia = .cd

    var body: some View {
        VStack(spacing: 0) {
            Picker("Media", selection: $selectedMedia) {
                ForEach(TargetMedia.allCases) { media in
                    Text(media.displayName).tag(media)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)

            ScrollView {
                VStack(spacing: 20) {
                    switch selectedMedia {
                    case .cd:
                        cdSections
                    case .dvd:
                        dvdSections
                    case .bluray:
                        bluraySections
                    }
                }
                .padding(24)
            }
        }
    }

    // MARK: - CD Sections

    @ViewBuilder
    private var cdSections: some View {
        DisclosureGroup("Audio CD", isExpanded: .constant(true)) {
            AudioCDSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)

        DisclosureGroup("Data CD") {
            DataCDSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)

        DisclosureGroup("Disc Image") {
            DiscImageBurnSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)
    }

    // MARK: - DVD Sections

    @ViewBuilder
    private var dvdSections: some View {
        DisclosureGroup("DVD Video", isExpanded: .constant(true)) {
            DVDVideoSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)

        DisclosureGroup("DVD Audio") {
            DVDAudioSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)

        DisclosureGroup("Data DVD") {
            DataDVDSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)
    }

    // MARK: - Blu-ray Sections

    @ViewBuilder
    private var bluraySections: some View {
        DisclosureGroup("Blu-ray Video", isExpanded: .constant(true)) {
            BlurayVideoSection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)

        DisclosureGroup("Data Blu-ray") {
            DataBluraySection()
                .padding(.top, 8)
        }
        .disclosureGroupStyle(.automatic)
    }
}
