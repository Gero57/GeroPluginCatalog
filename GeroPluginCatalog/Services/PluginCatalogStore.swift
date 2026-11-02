import Foundation
import SwiftUI

@MainActor
final class PluginCatalogStore: ObservableObject {
    @Published private(set) var installations: [PluginInstallation] = []
    @Published private(set) var manualPlugins: [ManualPlugin] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var scanMessage = "Ready to scan"
    @Published private(set) var artworkPaths: [String: String] = [:]
    @Published private(set) var artworkSearchMessage = ""
    @Published private(set) var searchingArtworkID: String?

    private let scanner = PluginScanner()
    private let artworkStore = ArtworkStore()
    private let manualCatalogURL: URL

    init() {
        artworkPaths = artworkStore.paths
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        manualCatalogURL = support.appendingPathComponent("GeroPluginCatalog/manual-plugins.json")
        loadManualPlugins()
    }

    func addManualPlugin(name: String, manufacturer: String, category: PluginCategory, format: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        manualPlugins.append(ManualPlugin(name: cleanName,
            manufacturer: manufacturer.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category, format: format))
        saveManualPlugins()
        scanMessage = "Manual plug-in added"
    }

    func chooseArtwork(for productID: String) {
        artworkStore.chooseImage(for: productID)
        artworkPaths = artworkStore.paths
    }

    func searchArtwork(for product: PluginProduct) async {
        guard searchingArtworkID == nil else { return }
        searchingArtworkID = product.id
        artworkSearchMessage = "Searching online for \(product.name)…"
        let message = await artworkStore.searchAndSaveImage(
            for: product.id, name: product.name, manufacturer: product.manufacturer)
        artworkPaths = artworkStore.paths
        artworkSearchMessage = message
        searchingArtworkID = nil
    }

    func scan() {
        guard !isScanning else { return }
        isScanning = true
        scanMessage = "Scanning plug-in folders…"
        Task.detached(priority: .userInitiated) { [scanner] in
            let result = scanner.scan()
            await MainActor.run {
                self.installations = result.installations
                self.lastScanDate = Date()
                self.isScanning = false
                self.scanMessage = result.inaccessibleFolders.isEmpty
                    ? "Scan completed · manual entries preserved"
                    : "Scan completed with \(result.inaccessibleFolders.count) unreadable folder(s) · manual entries preserved"
            }
        }
    }

    private func loadManualPlugins() {
        guard let data = try? Data(contentsOf: manualCatalogURL),
              let saved = try? JSONDecoder().decode([ManualPlugin].self, from: data) else { return }
        manualPlugins = saved
    }

    private func saveManualPlugins() {
        do {
            try FileManager.default.createDirectory(at: manualCatalogURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(manualPlugins)
            try data.write(to: manualCatalogURL, options: .atomic)
        } catch {
            scanMessage = "Could not save manual entries: \(error.localizedDescription)"
        }
    }
}
