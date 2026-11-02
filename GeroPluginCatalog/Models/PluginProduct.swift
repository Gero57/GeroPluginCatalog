import Foundation

struct PluginProduct: Identifiable, Hashable {
    /// One visual product groups matching plug-in names across VST2, VST3 and AU.
    let id: String
    var name: String
    var manufacturer: String?
    var category: PluginCategory
    var installations: [PluginInstallation]
    var artworkPath: String?
    var manualFormat: String? = nil

    static func catalog(from installations: [PluginInstallation], manual: [ManualPlugin] = []) -> [PluginProduct] {
        // Use manufacturer + normalized class name as the cross-format identity.
        // Bundle identifiers often differ between AU and VST3 versions of the same product.
        let groups = Dictionary(grouping: installations) { installation in
            let normalizedName = normalize(installation.name)
            let normalizedMaker = normalize(installation.manufacturer ?? "")
            return "name:\(normalizedMaker)|\(normalizedName)"
        }

        let scanned = groups.map { _, items in
            let sorted = items.sorted { $0.format.rawValue < $1.format.rawValue }
            let primary = sorted[0]
            let normalizedName = normalize(primary.name)

            // Keep the previous VST3-based artwork key where possible, so existing
            // artwork selections continue to resolve after formats are consolidated.
            let preferred = items.first(where: { $0.format == .vst3 && !($0.bundleIdentifier ?? "").isEmpty })
                ?? items.first(where: { !($0.bundleIdentifier ?? "").isEmpty })
            let productID: String
            if let bundleID = preferred?.bundleIdentifier {
                productID = "bundle:\(bundleID.lowercased())|class:\(normalizedName)"
            } else {
                productID = "name:\(normalize(primary.manufacturer ?? ""))|\(normalizedName)"
            }

            return PluginProduct(
                id: productID,
                name: primary.name,
                manufacturer: sorted.compactMap(\.manufacturer).first,
                category: PluginCategory.guess(from: primary.name),
                installations: sorted,
                artworkPath: nil
            )
        }

        let manuallyAdded = manual.map { item in
            PluginProduct(id: item.id, name: item.name, manufacturer: item.manufacturer,
                category: item.category, installations: [], artworkPath: nil, manualFormat: item.format)
        }
        return (scanned + manuallyAdded).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }
}
