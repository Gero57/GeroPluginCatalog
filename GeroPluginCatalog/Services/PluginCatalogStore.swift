import Foundation
import SwiftUI

@MainActor
final class PluginCatalogStore: ObservableObject {
    @Published private(set) var installations: [PluginInstallation] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var scanMessage = "Ready to scan"
    @Published private(set) var artworkPaths: [String: String] = [:]
    @Published private(set) var artworkSearchMessage = ""
    @Published private(set) var searchingArtworkID: String?

    private let scanner = PluginScanner()
    private let artworkStore = ArtworkStore()

    init() {
        artworkPaths = artworkStore.paths
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
            for: product.id,
            name: product.name,
            manufacturer: product.manufacturer
        )
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
                    ? "Scan completed"
                    : "Scan completed with \(result.inaccessibleFolders.count) unreadable folder(s)"
            }
        }
    }
}
