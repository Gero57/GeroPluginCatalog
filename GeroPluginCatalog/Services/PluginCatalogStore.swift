import Foundation
import SwiftUI

@MainActor
final class PluginCatalogStore: ObservableObject {
    @Published private(set) var installations: [PluginInstallation] = []
    @Published private(set) var manualPlugins: [ManualPlugin] = []
    @Published private(set) var products: [PluginProduct] = []
    @Published private(set) var categoryCounts: [PluginCategory: Int] = [:]
    @Published private(set) var formatCounts: [PluginFormat: Int] = [:]
    @Published private(set) var isScanning = false
    private var didStartLaunchScan = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var scanMessage = "Ready to scan"
    @Published private(set) var artworkPaths: [String: String] = [:]
    @Published private(set) var categoryOverrides: [String: PluginCategory] = [:]
    private let categoryOverridesURL: URL
    @Published private(set) var artworkSearchMessage = ""
    @Published private(set) var searchingArtworkID: String?

    private let scanner = PluginScanner()
    private let artworkStore = ArtworkStore()
    private let manualCatalogURL: URL

    init() {
        artworkPaths = artworkStore.paths
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let catalogFolder = support.appendingPathComponent("GeroPluginCatalog", isDirectory: true)
        manualCatalogURL = catalogFolder.appendingPathComponent("manual-plugins.json")
        categoryOverridesURL = catalogFolder.appendingPathComponent("category-overrides.json")
        loadManualPlugins()
        loadCategoryOverrides()
        rebuildCatalog()
    }

    func addManualPlugin(name: String, manufacturer: String, category: PluginCategory, format: String) {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        manualPlugins.append(ManualPlugin(name: cleanName,
            manufacturer: manufacturer.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category, format: format))
        saveManualPlugins()
        rebuildCatalog()
        scanMessage = "Manual plug-in added"
    }

    func setCategory(_ category: PluginCategory, for product: PluginProduct) {
        let key = PluginProduct.categoryOverrideKey(name: product.name, manufacturer: product.manufacturer)
        categoryOverrides[key] = category
        saveCategoryOverrides()
        rebuildCatalog()
        scanMessage = "Category saved for \(product.name)"
    }

    func deleteManualPlugins(ids: [String]) {
        guard !ids.isEmpty else { return }
        let deleting = Set(ids)
        manualPlugins.removeAll { deleting.contains($0.id) }
        saveManualPlugins()
        rebuildCatalog()
        scanMessage = "Manual catalog entry deleted"
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

    func scanOnLaunchIfNeeded() {
        guard !didStartLaunchScan else { return }
        didStartLaunchScan = true
        scan()
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
                self.rebuildCatalog()
                self.scanMessage = result.inaccessibleFolders.isEmpty
                    ? "Scan completed · manual entries preserved"
                    : "Scan completed with \(result.inaccessibleFolders.count) unreadable folder(s) · manual entries preserved"
            }
        }
    }

    /// Rebuilds the expensive grouped catalog only when its source data changes,
    /// never as a side effect of selecting a filter or opening a card.
    private func rebuildCatalog() {
        let newProducts = PluginProduct.catalog(from: installations, manual: manualPlugins)
        products = newProducts.map { product in
            var updated = product
            let key = PluginProduct.categoryOverrideKey(name: product.name, manufacturer: product.manufacturer)
            if let override = categoryOverrides[key] { updated.category = override }
            return updated
        }

        var categories: [PluginCategory: Int] = [:]
        var formats: [PluginFormat: Int] = [:]
        for product in newProducts {
            categories[product.category, default: 0] += 1
            for format in Set(product.installations.map(\.format)) {
                formats[format, default: 0] += 1
            }
            if let manualFormat = product.manualFormat {
                for label in manualFormat.components(separatedBy: " · ") {
                    if let format = PluginFormat.allCases.first(where: { $0.rawValue == label }) {
                        formats[format, default: 0] += 1
                    }
                }
            }
        }
        categoryCounts = categories
        formatCounts = formats
    }

    private func loadManualPlugins() {
        guard let data = try? Data(contentsOf: manualCatalogURL),
              let saved = try? JSONDecoder().decode([ManualPlugin].self, from: data) else { return }
        manualPlugins = saved
    }

    private func loadCategoryOverrides() {
        guard let data = try? Data(contentsOf: categoryOverridesURL),
              let saved = try? JSONDecoder().decode([String: PluginCategory].self, from: data) else { return }
        categoryOverrides = saved
    }

    private func saveCategoryOverrides() {
        do {
            try FileManager.default.createDirectory(at: categoryOverridesURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(categoryOverrides)
            try data.write(to: categoryOverridesURL, options: .atomic)
        } catch {
            scanMessage = "Could not save category changes: \(error.localizedDescription)"
        }
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
