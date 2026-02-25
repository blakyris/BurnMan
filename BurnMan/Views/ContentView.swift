import SwiftUI

// MARK: - Sidebar Section

enum SidebarSection: String, CaseIterable {
    case burn = "Graver"
    case copy = "Copier"
    case extract = "Extraire"
    case convert = "Convertir"
    case tools = "Outils"
}

// MARK: - Navigation Item

enum NavigationItem: String, Identifiable {
    // Graver
    case audioCD = "CD Audio"
    case discImage = "Image disque"
    case dataCD = "Disque de données"
    case videoDisc = "Disque vidéo"
    // Copier
    case copyCD = "Copier un disque"
    case createImage = "Créer une image disque"
    // Extraire
    case extractAudio = "Extraire les pistes audio"
    case extractVideo = "Extraire un film"
    // Convertir
    case convertImage = "Convertir une image disque"
    case convertFile = "Convertir un fichier"
    // Outils
    case eraseCDRW = "Effacer un disque"
    case generateCue = "Éditeur de métadonnées"

    var id: String { rawValue }

    var section: SidebarSection {
        switch self {
        case .audioCD, .discImage, .dataCD, .videoDisc:
            return .burn
        case .copyCD, .createImage:
            return .copy
        case .extractAudio, .extractVideo:
            return .extract
        case .convertImage, .convertFile:
            return .convert
        case .eraseCDRW, .generateCue:
            return .tools
        }
    }

    var icon: String {
        switch self {
        case .audioCD: return "music.note.list"
        case .discImage: return "opticaldisc"
        case .dataCD: return "folder.fill"
        case .videoDisc: return "play.rectangle"
        case .copyCD: return "doc.on.doc"
        case .createImage: return "externaldrive.badge.plus"
        case .extractAudio: return "waveform"
        case .extractVideo: return "film"
        case .convertImage: return "arrow.triangle.2.circlepath"
        case .convertFile: return "arrow.2.squarepath"
        case .eraseCDRW: return "eraser"
        case .generateCue: return "doc.badge.gearshape"
        }
    }

    static func items(for section: SidebarSection) -> [NavigationItem] {
        switch section {
        case .burn: return [.audioCD, .videoDisc, .dataCD, .discImage]
        case .copy: return [.copyCD, .createImage]
        case .extract: return [.extractAudio, .extractVideo]
        case .convert: return [.convertImage, .convertFile]
        case .tools: return [.eraseCDRW, .generateCue]
        }
    }
}

// MARK: - Content View

struct ContentView: View {
    @Environment(BurnManager.self) private var burnManager
    @Environment(DeviceManager.self) private var deviceManager
    @State private var selectedItem: NavigationItem? = .audioCD

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .task {
            await deviceManager.scanDevices()
        }
        .focusedSceneValue(\.refreshDevicesAction, {
            Task { await deviceManager.scanDevices() }
        })
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selectedItem) {
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Section {
                    ForEach(NavigationItem.items(for: section)) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                } header: {
                    Text(section.rawValue)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedItem {
        case .audioCD:
            AudioCDView()
        case .discImage:
            BurnView()
        case .generateCue:
            CueGeneratorView()
        case .videoDisc:
            VideoDiscView()
        case .dataCD:
            DataDiscView()
        case .copyCD:
            CopyDiscView()
        case .createImage:
            DiskImageView()
        case .extractAudio:
            ExtractAudioView()
        case .extractVideo:
            ExtractVideoView()
        case .eraseCDRW:
            EraseDiscView()
        case .convertImage, .convertFile:
            PlaceholderView(item: selectedItem!)
        case .none:
            VStack(spacing: 12) {
                Image(systemName: "opticaldisc.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
                Text("Choisis une action dans la barre latérale")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
