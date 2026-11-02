import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class ArtworkStore {
    private(set) var paths: [String: String] = [:]

    private let fileManager = FileManager.default
    private let folderURL: URL
    private let indexURL: URL

    init() {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        folderURL = support.appendingPathComponent("GeroPluginCatalog/Artwork", isDirectory: true)
        indexURL = support.appendingPathComponent("GeroPluginCatalog/artwork-index.json")
        loadIndex()
    }

    func chooseImage(for productID: String) {
        let panel = NSOpenPanel()
        panel.title = "Choose plug-in artwork"
        panel.message = "Select an image for this plug-in. The image will be copied into the catalog."
        panel.allowedContentTypes = [.png, .jpeg, .tiff, .image]
        panel.allowsOtherFileTypes = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing { sourceURL.stopAccessingSecurityScopedResource() }
        }

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
            let destination = folderURL.appendingPathComponent(fileKey(productID) + "." + ext)
            if let oldPath = paths[productID], oldPath != destination.path {
                try? fileManager.removeItem(atPath: oldPath)
            }
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: sourceURL, to: destination)
            paths[productID] = destination.path
            saveIndex()
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not add artwork"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else { return }
        paths = decoded.filter { fileManager.fileExists(atPath: $0.value) }
    }

    private func saveIndex() {
        do {
            try fileManager.createDirectory(
                at: indexURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(paths)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not save catalog artwork"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    private func fileKey(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }
}
