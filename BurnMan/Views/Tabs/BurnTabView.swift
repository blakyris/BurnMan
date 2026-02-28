import SwiftUI

enum BurnMode: String, CaseIterable, Identifiable {
    case audioCd = "Audio CD"
    case dataCd = "Data CD"
    case discImage = "Disc Image"
    case dvdVideo = "DVD Video"
    case dvdAudio = "DVD Audio"
    case dataDvd = "Data DVD"
    case blurayVideo = "Blu-ray Video"
    case dataBluray = "Data Blu-ray"

    var id: String { rawValue }

    static func modes(for media: TargetMedia) -> [BurnMode] {
        switch media {
        case .cd: [.audioCd, .dataCd, .discImage]
        case .dvd: [.dvdVideo, .dvdAudio, .dataDvd]
        case .bluray: [.blurayVideo, .dataBluray]
        }
    }

    static func defaultMode(for media: TargetMedia) -> BurnMode {
        modes(for: media).first!
    }
}

struct BurnTabView: View {
    // Managers for unsaved-work detection
    @Environment(AudioCDManager.self) private var audioCDManager
    @Environment(DataDiscManager.self) private var dataDiscManager
    @Environment(VideoDiscManager.self) private var videoDiscManager
    @Environment(DiskImageManager.self) private var diskImageManager
    @Environment(MediaPlayerService.self) private var mediaPlayerService

    @State private var selectedMedia: TargetMedia? = nil
    @State private var selectedMode: BurnMode = .audioCd
    @State private var showBackAlert = false

    private var hasUnsavedWork: Bool {
        audioCDManager.hasContent
            || dataDiscManager.hasContent
            || videoDiscManager.hasContent
            || diskImageManager.hasContent
            || mediaPlayerService.playingTrackID != nil
    }

    private var validatedMode: Binding<BurnMode> {
        Binding(
            get: {
                let media = selectedMedia ?? .cd
                let modes = BurnMode.modes(for: media)
                return modes.contains(selectedMode) ? selectedMode : BurnMode.defaultMode(for: media)
            },
            set: { selectedMode = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let media = selectedMedia {
                modeView(for: media)
            } else {
                mediaPickerView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedMedia)
        .alert("Leave this view?", isPresented: $showBackAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) {
                resetAll()
                selectedMedia = nil
            }
        } message: {
            Text("Content has been added. Leaving this view will discard all current data.")
        }
    }

    // MARK: - Level 1: Media Card Picker

    private var mediaPickerView: some View {
        VStack {
            Spacer()
            HStack(alignment: .top) {
                Spacer()
                MediaCard(
                    media: .cd,
                    icon: "opticaldisc",
                    color: .blue,
                    quickLinks: [
                        ("Audio CD", .audioCd),
                        ("Data CD", .dataCd),
                        ("Disc Image", .discImage),
                    ],
                    onSelectMedia: { selectMedia(.cd) },
                    onSelectMode: { selectMedia(.cd, mode: $0) }
                )
                Spacer()
                MediaCard(
                    media: .dvd,
                    icon: "opticaldisc.fill",
                    color: .orange,
                    quickLinks: [
                        ("DVD Video", .dvdVideo),
                        ("Data DVD", .dataDvd),
                    ],
                    onSelectMedia: { selectMedia(.dvd) },
                    onSelectMode: { selectMedia(.dvd, mode: $0) }
                )
                Spacer()
                MediaCard(
                    media: .bluray,
                    icon: "opticaldisc.fill",
                    color: .purple,
                    quickLinks: [
                        ("Blu-ray Video", .blurayVideo),
                        ("Data Blu-ray", .dataBluray),
                    ],
                    onSelectMedia: { selectMedia(.bluray) },
                    onSelectMode: { selectMedia(.bluray, mode: $0) }
                )
                Spacer()
            }
            .padding(.horizontal, 24)
            Spacer()
        }
    }

    private func selectMedia(_ media: TargetMedia, mode: BurnMode? = nil) {
        selectedMode = mode ?? BurnMode.defaultMode(for: media)
        selectedMedia = media
    }

    private func resetAll() {
        audioCDManager.reset()
        dataDiscManager.reset()
        videoDiscManager.reset()
        diskImageManager.reset()
        mediaPlayerService.stop()
    }

    // MARK: - Level 2: Mode View

    @ViewBuilder
    private func modeView(for media: TargetMedia) -> some View {
        HStack {
            Button {
                if hasUnsavedWork {
                    showBackAlert = true
                } else {
                    selectedMedia = nil
                }
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)

        Picker("", selection: validatedMode) {
            ForEach(BurnMode.modes(for: media)) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 24)
        .padding(.vertical, 8)

        ScrollView {
            VStack(spacing: 20) {
                switch validatedMode.wrappedValue {
                case .audioCd:      AudioCDSection()
                case .dataCd:       DataCDSection()
                case .discImage:    DiscImageBurnSection()
                case .dvdVideo:     DVDVideoSection()
                case .dvdAudio:     DVDAudioSection()
                case .dataDvd:      DataDVDSection()
                case .blurayVideo:  BlurayVideoSection()
                case .dataBluray:   DataBluraySection()
                }
            }
            .padding(24)
        }
    }
}

// MARK: - Media Card

private struct MediaCard: View {
    let media: TargetMedia
    let icon: String
    let color: Color
    let quickLinks: [(label: String, mode: BurnMode)]
    let onSelectMedia: () -> Void
    let onSelectMode: (BurnMode) -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Card — clickable, equal height (only icon + title)
            Button(action: onSelectMedia) {
                VStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.system(size: 80))
                    Text(media.displayName)
                        .font(.headline)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.background)
                    .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )

            // Quick links — outside card, centered
            VStack(alignment: .leading, spacing: 6) {
                ForEach(quickLinks, id: \.label) { link in
                    Button {
                        onSelectMode(link.mode)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 5))
                            Text(link.label)
                        }
                        .font(.subheadline)
                        .foregroundStyle(color)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
