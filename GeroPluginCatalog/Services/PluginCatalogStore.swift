import Foundation
import SwiftUI
import AppKit

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
    @Published private(set) var importedReportCount = 0

    private let scanner = PluginScanner()
    private let artworkStore = ArtworkStore()
    private let manualCatalogURL: URL
    private let reportImportURL: URL
    private var reportInstallations: [PluginInstallation] = []

    init() {
        artworkPaths = artworkStore.paths
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let catalogFolder = support.appendingPathComponent("GeroPluginCatalog", isDirectory: true)
        manualCatalogURL = catalogFolder.appendingPathComponent("manual-plugins.json")
        categoryOverridesURL = catalogFolder.appendingPathComponent("category-overrides.json")
        reportImportURL = catalogFolder.appendingPathComponent("cubase-report-plugins.json")
        loadManualPlugins()
        loadCategoryOverrides()
        loadReportPlugins()
        rebuildCatalog()
    }

    func importCubaseReport() {
        let panel = NSOpenPanel()
        panel.title = "Import Cubase Plug-in Report"
        panel.message = "Select the text report created by Cubase 13 Plug-in Manager."
        panel.allowedFileTypes = ["txt"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = PluginReportImporter().parse(text)
            guard !result.installations.isEmpty else {
                scanMessage = "No plug-ins found in the selected report"
                return
            }
            reportInstallations = result.installations
            importedReportCount = result.installations.count
            saveReportPlugins()
            installations = mergeInstallations(installations, reportInstallations)
            rebuildCatalog()
            scanMessage = "Cubase report imported · \(result.installations.count) plug-ins"
        } catch {
            scanMessage = "Could not read Cubase report: \(error.localizedDescription)"
        }
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
        refreshArtworkPaths()
    }

    func searchArtwork(for product: PluginProduct) async {
        guard searchingArtworkID == nil else { return }
        searchingArtworkID = product.id
        artworkSearchMessage = "Searching online for \(product.name)…"
        let message = await artworkStore.searchAndSaveImage(
            for: product.id, name: product.name, manufacturer: product.manufacturer)
        refreshArtworkPaths()
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
                self.installations = self.mergeInstallations(result.installations, self.reportInstallations)
                self.lastScanDate = Date()
                self.isScanning = false
                self.rebuildCatalog()
                self.scanMessage = result.inaccessibleFolders.isEmpty
                    ? "Scan completed · imported Cubase report preserved"
                    : "Scan completed with \(result.inaccessibleFolders.count) unreadable folder(s) · report preserved"
            }
        }
    }

    private func mergeInstallations(_ first: [PluginInstallation], _ second: [PluginInstallation]) -> [PluginInstallation] {
        Dictionary((first + second).map { ($0.id, $0) }, uniquingKeysWith: { _, report in report })
            .values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func loadReportPlugins() {
        guard let data = try? Data(contentsOf: reportImportURL),
              let saved = try? JSONDecoder().decode([PluginInstallation].self, from: data) else { return }
        reportInstallations = saved
        importedReportCount = saved.count
        installations = mergeInstallations(installations, saved)
    }

    private func saveReportPlugins() {
        do {
            try FileManager.default.createDirectory(at: reportImportURL.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try JSONEncoder().encode(reportInstallations).write(to: reportImportURL, options: .atomic)
        } catch {
            scanMessage = "Could not save imported Cubase report: \(error.localizedDescription)"
        }
    }

    private func rebuildCatalog() {
        let newProducts = PluginProduct.catalog(from: installations, manual: manualPlugins)
        products = newProducts.map { product in
            var updated = product
            let key = PluginProduct.categoryOverrideKey(name: product.name, manufacturer: product.manufacturer)
            if let override = categoryOverrides[key] { updated.category = override }
            return updated
        }
        refreshArtworkPaths()

        var categories: [PluginCategory: Int] = [:]
        var formats: [PluginFormat: Int] = [:]
        for product in products {
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

    private func refreshArtworkPaths() {
        var refreshed = artworkStore.paths
        for product in products {
            if refreshed[product.id] != nil { continue }
            let nameKey = PluginProduct.categoryOverrideKey(name: product.name, manufacturer: nil)
            let oldKeys = artworkStore.paths.keys.filter { key in
                key.hasSuffix("|class:\(nameKey)") ||
                key.hasSuffix("|\(nameKey)") ||
                product.manualEntryIDs.contains(key)
            }
            if let oldKey = oldKeys.first, let path = artworkStore.paths[oldKey] {
                refreshed[product.id] = path
            }
        }
        artworkPaths = refreshed
    }

    private func loadManualPlugins() {
        guard let data = try? Data(contentsOf: manualCatalogURL),
              let saved = try? JSONDecoder().decode([ManualPlugin].self, from: data) else { return }
        manualPlugins = saved
    }

    private func loadCategoryOverrides() {
        guard let data = try? Data(contentsOf: categoryOverridesURL),
              let saved = try? JSONDecoder().decode([String: PluginCategory].self, from: data) else { return }
        var migrated: [String: PluginCategory] = [:]
        for (key, category) in saved {
            let name = key.contains("|") ? (key.split(separator: "|").last.map(String.init) ?? key) : key
            migrated[PluginProduct.categoryOverrideKey(name: name, manufacturer: nil)] = category
        }
        categoryOverrides = migrated
        if migrated != saved { saveCategoryOverrides() }
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
