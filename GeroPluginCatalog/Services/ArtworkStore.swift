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

    func searchAndSaveImage(for productID: String, name: String, manufacturer: String?) async -> String {
        var query = "\"\(name)\""
        if let manufacturer, !manufacturer.isEmpty { query += " \(manufacturer)" }
        query += " audio plugin official product"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://html.duckduckgo.com/html/?q=" + encoded) else {
            return "Search URL could not be created"
        }

        do {
            var request = URLRequest(url: searchURL)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15
            let (searchData, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: searchData, encoding: .utf8) else {
                return "The search engine returned an unreadable page"
            }
            let pattern = #"<a[^>]+class=["'][^"']*result__a[^"']*["'][^>]+href=["']([^"']+)["']"#
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                return "Could not read search results"
            }
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            var pages: [URL] = []
            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let raw = String(html[range])
                let destination: String
                if let components = URLComponents(string: raw),
                   let redirect = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
                    destination = redirect
                } else {
                    destination = raw
                }
                guard let url = URL(string: destination),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host?.lowercased(),
                      !host.contains("duckduckgo.com"),
                      !host.contains("youtube.com"),
                      !host.contains("facebook.com") else { continue }
                pages.append(url)
            }
            guard !pages.isEmpty else { return "No matching product pages were found" }

            for page in pages.prefix(5) {
                var pageRequest = URLRequest(url: page)
                pageRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                pageRequest.timeoutInterval = 12
                guard let (pageData, _) = try? await URLSession.shared.data(for: pageRequest),
                      let pageHTML = String(data: pageData, encoding: .utf8) else { continue }
                let metaPattern = #"<meta\b[^>]*(?:property|name)=["'](?:og:image|twitter:image)["'][^>]*>"#
                guard let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive]) else { continue }
                for meta in metaRegex.matches(in: pageHTML, range: NSRange(pageHTML.startIndex..., in: pageHTML)) {
                    guard let metaRange = Range(meta.range, in: pageHTML) else { continue }
                    let tag = String(pageHTML[metaRange])
                    let contentPattern = #"content=["']([^"']+)["']"#
                    guard let contentRegex = try? NSRegularExpression(pattern: contentPattern, options: [.caseInsensitive]),
                          let content = contentRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                          let valueRange = Range(content.range(at: 1), in: tag) else { continue }
                    let value = String(tag[valueRange])
                    guard let imageURL = URL(string: value, relativeTo: page)?.absoluteURL else { continue }
                    var imageRequest = URLRequest(url: imageURL)
                    imageRequest.setValue("GeroPluginCatalog/1.0", forHTTPHeaderField: "User-Agent")
                    imageRequest.timeoutInterval = 15
                    guard let (imageData, response) = try? await URLSession.shared.data(for: imageRequest),
                          let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          let image = NSImage(data: imageData),
                          image.size.width >= 100, image.size.height >= 60 else { continue }
                    do {
                        try saveImage(imageData, for: productID, preferredExtension: imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension)
                        return "Artwork found and saved"
                    } catch {
                        return "Image found, but could not be saved: \(error.localizedDescription)"
                    }
                }
            }
            return "No suitable image found. You can choose a screenshot manually."
        } catch {
            return "Online search failed: \(error.localizedDescription)"
        }
    }

    private func saveImage(_ data: Data, for productID: String, preferredExtension: String) throws {
        guard NSImage(data: data) != nil else {
            throw NSError(domain: "GeroPluginCatalog.Artwork", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "The downloaded file is not a readable image"])
        }
        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let ext = preferredExtension.isEmpty ? "jpg" : preferredExtension.lowercased()
        let destination = folderURL.appendingPathComponent(fileKey(productID) + "." + ext)
        if let oldPath = paths[productID], oldPath != destination.path {
            try? fileManager.removeItem(atPath: oldPath)
        }
        if fileManager.fileExists(atPath: destination.path) { try fileManager.removeItem(at: destination) }
        try data.write(to: destination, options: .atomic)
        paths[productID] = destination.path
        saveIndex()
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
