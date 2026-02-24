import SwiftUI
import UniformTypeIdentifiers

struct CueGeneratorView: View {
    @Environment(BurnManager.self) private var burnManager
    @State private var scanState = ScanState()
    @State private var isScanning = false
    @State private var scanProgress: Double = 0
    @State private var isDragTargeted = false
    @State private var savedURL: URL?
    @State private var showSaveSuccess = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // File selection
                fileSelectionSection

                // Analysis results
                if !scanState.tracks.isEmpty {
                    tracksSection
                }

                // Generated CUE preview
                if !scanState.generatedCue.isEmpty {
                    cuePreviewSection
                }

                // Error
                if let error = scanState.errorMessage {
                    errorSection(error)
                }

                // Actions
                if !scanState.tracks.isEmpty {
                    actionsSection
                }
            }
            .padding(24)
        }
        .navigationTitle("Générateur CUE")
        .focusedSceneValue(\.saveCueAction, scanState.tracks.isEmpty ? nil : { saveCueFile() })
    }

    // MARK: - File Selection

    private var fileSelectionSection: some View {
        SectionContainer(title: "Fichiers source", systemImage: "doc.on.doc") {
            VStack(spacing: 16) {
                if scanState.binFiles.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.badge.plus")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)

                        Text("Sélectionne des fichiers .bin")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text("Un seul fichier (multi-pistes) ou plusieurs fichiers (un par piste)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)

                        HStack(spacing: 12) {
                            Button {
                                selectFiles()
                            } label: {
                                Label("Fichiers .bin", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(.glass)

                            Button {
                                selectFolder()
                            } label: {
                                Label("Dossier", systemImage: "folder")
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(24)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(scanState.binFiles.count) fichier(s) .bin sélectionné(s)")
                                .font(.headline)

                            Text(String(format: "Taille totale : %.1f Mo", scanState.totalSizeMB))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Changer") {
                            scanState.resetAll()
                        }
                    }
                    .padding(8)

                    // Scan button
                    if scanState.tracks.isEmpty {
                        Button {
                            analyzeFiles()
                        } label: {
                            Label("Analyser les fichiers", systemImage: "waveform.badge.magnifyingglass")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(isScanning)
                    }

                    // Scan progress
                    if isScanning {
                        VStack(spacing: 8) {
                            ProgressView(value: scanProgress)
                                .tint(.blue)
                            Text("Analyse en cours...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
            handleDrop(providers)
        }
        .dropHighlight(isTargeted: isDragTargeted)
    }

    // MARK: - Tracks Section

    private var tracksSection: some View {
        let dataCount = scanState.tracks.count(where: { $0.mode != .audio })
        let audioCount = scanState.tracks.count(where: { $0.mode == .audio })
        return SectionContainer(title: "Pistes détectées (\(dataCount) data, \(audioCount) audio)", systemImage: "music.note.list") {
            VStack(spacing: 0) {
                ForEach(scanState.tracks) { track in
                    TrackRowView(
                        track: track,
                        showDuration: scanState.binFiles.count == 1,
                        showMSF: scanState.binFiles.count == 1,
                        showFileName: scanState.binFiles.count != 1
                    )

                    if track.id != scanState.tracks.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - CUE Preview

    private var cuePreviewSection: some View {
        SectionContainer(title: "Aperçu du .cue", systemImage: "doc.text") {
            VStack(alignment: .leading, spacing: 8) {
                Text(scanState.generatedCue)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contextMenu {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(scanState.generatedCue, forType: .string)
                        } label: {
                            Label("Copier le contenu CUE", systemImage: "doc.on.doc")
                        }
                    }
            }
        }
    }

    // MARK: - Error

    private func errorSection(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.red)

            Spacer()

            Button {
                scanState.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .statusBadge(color: .red)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    saveCueFile()
                } label: {
                    Label("Enregistrer le .cue", systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    saveCueAndLoadForBurn()
                } label: {
                    Label("Enregistrer et graver", systemImage: "flame")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .overlay {
                if showSaveSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Enregistré !")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .successToastStyle()
                    .transition(.opacity.combined(with: .scale))
                }
            }
        }
    }

    // MARK: - Helpers

    private func computeTotalSize(for urls: [URL]) -> Double {
        urls.reduce(0.0) { sum, url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return sum + Double(size) / 1_048_576
        }
    }

    // MARK: - File Operations

    private func selectFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "bin")!]
        panel.message = "Sélectionne un ou plusieurs fichiers .bin"

        if panel.runModal() == .OK {
            let files = panel.urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
            scanState.binFiles = files
            scanState.totalSizeMB = computeTotalSize(for: files)
            scanState.reset()
        }
    }

    private func selectFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Sélectionne un dossier contenant des fichiers .bin"

        if panel.runModal() == .OK, let url = panel.url {
            let contents = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil
            )
            let files = (contents ?? [])
                .filter { $0.pathExtension.lowercased() == "bin" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            scanState.binFiles = files
            scanState.totalSizeMB = computeTotalSize(for: files)
            scanState.reset()

            if scanState.binFiles.isEmpty {
                scanState.errorMessage = "Aucun fichier .bin trouvé dans ce dossier."
            }
        }
    }

    private func analyzeFiles() {
        isScanning = true
        scanState.errorMessage = nil
        scanProgress = 0

        let files = scanState.binFiles
        Task.detached {
            do {
                let result: [TrackInfo]
                let isMultiTrack: Bool

                if files.count == 1 {
                    // Single file - scan for multiple tracks
                    isMultiTrack = true
                    result = try CueGenerator.scanMultiTrack(at: files[0]) { pct in
                        Task { @MainActor in
                            scanProgress = pct
                        }
                    }
                } else {
                    // Multiple files
                    isMultiTrack = false
                    result = try CueGenerator.analyzeMultipleFiles(urls: files)
                }

                let cueContent = CueGenerator.generateCueContent(
                    tracks: result,
                    isMultiTrack: isMultiTrack
                )

                await MainActor.run {
                    scanState.tracks = result
                    scanState.generatedCue = cueContent
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    scanState.errorMessage = error.localizedDescription
                    isScanning = false
                }
            }
        }
    }

    private func saveCueFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "cue")!]

        // Proposer un nom basé sur le premier .bin ou le dossier
        if let firstFile = scanState.binFiles.first {
            if scanState.binFiles.count == 1 {
                panel.nameFieldStringValue = firstFile.deletingPathExtension().lastPathComponent + ".cue"
            } else {
                let folder = firstFile.deletingLastPathComponent().lastPathComponent
                panel.nameFieldStringValue = folder + ".cue"
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try CueGenerator.writeCueFile(content: scanState.generatedCue, to: url)
                savedURL = url

                withAnimation {
                    showSaveSuccess = true
                }
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation {
                        showSaveSuccess = false
                    }
                }
            } catch {
                scanState.errorMessage = "Erreur lors de l'enregistrement : \(error.localizedDescription)"
            }
        }
    }

    private func saveCueAndLoadForBurn() {
        saveCueFile()
        if let url = savedURL {
            burnManager.loadCueFile(url: url)
        }
    }

    // MARK: - Drag & Drop

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task {
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    if url.pathExtension.lowercased() == "bin" {
                        urls.append(url)
                    } else if url.hasDirectoryPath {
                        let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
                        urls.append(contentsOf: (contents ?? []).filter { $0.pathExtension.lowercased() == "bin" })
                    }
                }
            }
            if !urls.isEmpty {
                let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
                scanState.binFiles = sorted
                scanState.totalSizeMB = computeTotalSize(for: sorted)
                scanState.reset()
            }
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                let url = (item as? Data).flatMap { URL(dataRepresentation: $0, relativeTo: nil) }
                continuation.resume(returning: url)
            }
        }
    }
}

// MARK: - Scan State

private struct ScanState {
    var binFiles: [URL] = []
    var tracks: [TrackInfo] = []
    var generatedCue: String = ""
    var errorMessage: String?
    var totalSizeMB: Double = 0

    /// Clears analysis results and error, keeps binFiles and totalSizeMB
    mutating func reset() {
        tracks = []
        generatedCue = ""
        errorMessage = nil
    }

    /// Resets everything back to initial state
    mutating func resetAll() {
        binFiles = []
        tracks = []
        generatedCue = ""
        errorMessage = nil
        totalSizeMB = 0
    }
}
