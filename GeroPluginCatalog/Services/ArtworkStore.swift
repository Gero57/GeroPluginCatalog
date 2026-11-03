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
        // Use a broad product query: exact quoted searches can return too few results.
        var terms = [name]
        if let manufacturer, !manufacturer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            terms.append(manufacturer)
        }
        terms.append("audio plugin")
        let query = terms.joined(separator: " ")

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://html.duckduckgo.com/html/?q=" + encoded) else {
            return "Search URL could not be created"
        }

        do {
            var request = URLRequest(url: searchURL)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
            request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15
            let (searchData, searchResponse) = try await URLSession.shared.data(for: request)
            guard let searchHTTP = searchResponse as? HTTPURLResponse,
                  (200...299).contains(searchHTTP.statusCode) else {
                let status = (searchResponse as? HTTPURLResponse)?.statusCode ?? -1
                return "Search service returned HTTP \(status)"
            }
            guard let html = String(data: searchData, encoding: .utf8) else {
                return "The search engine returned an unreadable page"
            }

            // DuckDuckGo has changed its result markup more than once. Read every
            // anchor href and decode its redirect, rather than depending on class/order.
            let anchorPattern = #"<a\b[^>]*>"#
            let hrefPattern = #"href\s*=\s*["']([^"']+)["']"#
            guard let anchorRegex = try? NSRegularExpression(pattern: anchorPattern, options: [.caseInsensitive]),
                  let hrefRegex = try? NSRegularExpression(pattern: hrefPattern, options: [.caseInsensitive]) else {
                return "Could not read search results"
            }

            var pages: [URL] = []
            var seen = Set<String>()
            let anchors = anchorRegex.matches(in: html, range: NSRange(html.startIndex..., in: html))
            for anchor in anchors {
                guard let tagRange = Range(anchor.range, in: html) else { continue }
                let tag = String(html[tagRange])
                guard let href = hrefRegex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
                      let valueRange = Range(href.range(at: 1), in: tag) else { continue }
                var raw = String(tag[valueRange]).replacingOccurrences(of: "&amp;", with: "&")
                if raw.hasPrefix("//") { raw = "https:" + raw }

                var destination = raw
                if let components = URLComponents(string: raw),
                   let redirect = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
                    destination = redirect
                }
                guard let url = URL(string: destination),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                      let host = url.host?.lowercased(),
                      !host.contains("duckduckgo.com"),
                      !host.contains("youtube.com"),
                      !host.contains("facebook.com"),
                      !host.contains("instagram.com"),
                      seen.insert(url.absoluteString).inserted else { continue }
                pages.append(url)
            }

            guard !pages.isEmpty else {
                return "The search service responded, but returned no readable result links (HTTP \(searchHTTP.statusCode), \(searchData.count) bytes)"
            }

            // Inspect more results, but keep each request bounded so the search stays quick.
            for page in pages.prefix(8) {
                var pageRequest = URLRequest(url: page)
                pageRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                pageRequest.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
                pageRequest.timeoutInterval = 8
                guard let (pageData, pageResponse) = try? await URLSession.shared.data(for: pageRequest),
                      let pageHTTP = pageResponse as? HTTPURLResponse,
                      (200...299).contains(pageHTTP.statusCode),
                      let pageHTML = String(data: pageData, encoding: .utf8) else { continue }

                // Accept either attribute order: property/name may follow content.
                let metaPattern = #"<meta\b[^>]*>"#
                let attributePattern = #"([a-zA-Z:_-]+)\s*=\s*["']([^"']*)["']"#
                guard let metaRegex = try? NSRegularExpression(pattern: metaPattern, options: [.caseInsensitive]),
                      let attributeRegex = try? NSRegularExpression(pattern: attributePattern, options: [.caseInsensitive]) else { continue }

                for meta in metaRegex.matches(in: pageHTML, range: NSRange(pageHTML.startIndex..., in: pageHTML)) {
                    guard let metaRange = Range(meta.range, in: pageHTML) else { continue }
                    let tag = String(pageHTML[metaRange])
                    var attributes: [String: String] = [:]
                    for match in attributeRegex.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
                        guard let keyRange = Range(match.range(at: 1), in: tag),
                              let valueRange = Range(match.range(at: 2), in: tag) else { continue }
                        attributes[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
                    }
                    let property = (attributes["property"] ?? attributes["name"] ?? "").lowercased()
                    guard property == "og:image" || property == "twitter:image",
                          let imageValue = attributes["content"],
                          let imageURL = URL(string: imageValue.replacingOccurrences(of: "&amp;", with: "&"), relativeTo: page)?.absoluteURL else { continue }

                    var imageRequest = URLRequest(url: imageURL)
                    imageRequest.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
                    imageRequest.timeoutInterval = 10
                    guard let (imageData, response) = try? await URLSession.shared.data(for: imageRequest),
                          let http = response as? HTTPURLResponse,
                          (200...299).contains(http.statusCode),
                          let image = NSImage(data: imageData),
                          image.size.width >= 80, image.size.height >= 50 else { continue }
                    do {
                        try saveImage(imageData, for: productID,
                                      preferredExtension: imageURL.pathExtension.isEmpty ? "jpg" : imageURL.pathExtension)
                        return "Artwork found and saved"
                    } catch {
                        return "Image found, but could not be saved: \(error.localizedDescription)"
                    }
                }
            }
            return "Found \(pages.count) result pages, but none exposed a downloadable product image. You can choose a screenshot manually."
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
