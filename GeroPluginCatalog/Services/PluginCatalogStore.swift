import Foundation
import SwiftUI

@MainActor
final class PluginCatalogStore: ObservableObject {
    @Published private(set) var installations: [PluginInstallation] = []
    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var scanMessage = "Ready to scan"

    private let scanner = PluginScanner()

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
