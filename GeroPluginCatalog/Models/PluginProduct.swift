import Foundation

struct PluginProduct: Identifiable, Hashable {
    /// A product groups installations of the same plug-in class across formats.
    let id: String
    var name: String
    var manufacturer: String?
    var category: PluginCategory
    var installations: [PluginInstallation]
    var artworkPath: String?
    var manualFormat: String? = nil

    static func catalog(from installations: [PluginInstallation], manual: [ManualPlugin] = []) -> [PluginProduct] {
        let groups = Dictionary(grouping: installations) { installation in
            let normalizedName = installation.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let bundleID = installation.bundleIdentifier, !bundleID.isEmpty {
                // A VST3 bundle may contain several distinct plug-in classes.
                return "bundle:\(bundleID.lowercased())|class:\(normalizedName)"
            }
            let normalizedMaker = (installation.manufacturer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return "name:\(normalizedMaker)|\(normalizedName)"
        }

        let scanned = groups.map { key, items in
            let sorted = items.sorted { $0.format.rawValue < $1.format.rawValue }
            let primary = sorted[0]
            return PluginProduct(id: key, name: primary.name,
                manufacturer: sorted.compactMap(\.manufacturer).first,
                category: PluginCategory.guess(from: primary.name),
                installations: sorted, artworkPath: nil)
        }

        let manuallyAdded = manual.map { item in
            PluginProduct(id: item.id, name: item.name, manufacturer: item.manufacturer,
                category: item.category, installations: [], artworkPath: nil, manualFormat: item.format)
        }
        return (scanned + manuallyAdded).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
