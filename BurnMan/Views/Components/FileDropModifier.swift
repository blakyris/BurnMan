import SwiftUI

/// ViewModifier that encapsulates file drag-and-drop handling:
/// `@State isDragTargeted`, NSItemProvider → URL parsing, optional extension filtering,
/// batched URL collection via `DropURLCollector`, and `.dropHighlight`.
struct FileDropModifier: ViewModifier {
    var extensions: Set<String>?
    var onDrop: @MainActor ([URL]) -> Void

    @State private var isDragTargeted = false

    func body(content: Content) -> some View {
        content
            .onDrop(of: [.fileURL], isTargeted: $isDragTargeted) { providers in
                handleDrop(providers)
            }
            .dropHighlight(isTargeted: isDragTargeted)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        let allowedExtensions = extensions
        let handler = onDrop

        let collector = DropURLCollector(total: providers.count) { urls in
            handler(urls)
        }

        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data,
                   let parsed = URL(dataRepresentation: data, relativeTo: nil) {
                    if let exts = allowedExtensions {
                        if exts.contains(parsed.pathExtension.lowercased()) {
                            url = parsed
                        }
                    } else {
                        url = parsed
                    }
                }
                collector.collected(url: url)
            }
        }
        return true
    }
}

extension View {
    func fileDrop(
        extensions: Set<String>? = nil,
        onDrop: @escaping @MainActor ([URL]) -> Void
    ) -> some View {
        modifier(FileDropModifier(extensions: extensions, onDrop: onDrop))
    }
}
