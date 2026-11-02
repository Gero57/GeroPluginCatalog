import Foundation

struct PluginProduct: Identifiable, Hashable {
    /// A product groups all installed formats/locations for the same plug-in.
    let id: String
    var name: String
    var manufacturer: String?
    var category: PluginCategory
    var installations: [PluginInstallation]
    var artworkPath: String?

    static func catalog(from installations: [PluginInstallation]) -> [PluginProduct] {
        let groups = Dictionary(grouping: installations) { installation in
            if let bundleID = installation.bundleIdentifier, !bundleID.isEmpty {
                return "bundle:\(bundleID.lowercased())"
            }
            let normalizedName = installation.name
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            let normalizedMaker = (installation.manufacturer ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            return "name:\(normalizedMaker)|\(normalizedName)"
        }

        return groups.map { key, items in
            let sorted = items.sorted { $0.format.rawValue < $1.format.rawValue }
            let primary = sorted[0]
            return PluginProduct(
                id: key,
                name: primary.name,
                manufacturer: sorted.compactMap(\.manufacturer).first,
                category: PluginCategory.guess(from: primary.name),
                installations: sorted,
                artworkPath: nil
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
