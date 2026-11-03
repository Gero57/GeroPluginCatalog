import Foundation

struct PluginProduct: Identifiable, Hashable {
    /// A single visual card per normalized plug-in name, with all installed formats attached.
    let id: String
    var name: String
    var manufacturer: String?
    var category: PluginCategory
    var installations: [PluginInstallation]
    var artworkPath: String?
    var manualFormat: String? = nil
    var manualEntryIDs: [String] = []

    static func catalog(from installations: [PluginInstallation], manual: [ManualPlugin] = []) -> [PluginProduct] {
        // The plug-in name is the primary identity. AU/VST metadata often differs
        // even when both bundles are the same product, so vendor and bundle IDs
        // must never create separate cards for an identical normalized name.
        let byName = Dictionary(grouping: installations) { normalize($0.name) }
        var scanned: [PluginProduct] = []

        for (nameKey, items) in byName {
            let sorted = items.sorted {
                if $0.format != $1.format { return $0.format.rawValue < $1.format.rawValue }
                return $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending
            }
            guard let primary = sorted.first else { continue }

            // Prefer a non-empty manufacturer, then the most frequently reported one.
            let makerCounts = Dictionary(grouping: sorted.compactMap { item -> String? in
                guard let maker = item.manufacturer?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !maker.isEmpty else { return nil }
                return maker
            }, by: normalize)
            let manufacturer = makerCounts.values
                .sorted { $0.count > $1.count }
                .first?.first

            // Remove repeated records pointing to the same format and bundle path.
            var seenInstallations = Set<String>()
            let uniqueInstallations = sorted.filter { item in
                let key = "\(item.format.rawValue)|\(item.path)|\(normalize(item.name))"
                return seenInstallations.insert(key).inserted
            }

            scanned.append(PluginProduct(
                id: "plugin:\(nameKey)",
                name: primary.name,
                manufacturer: manufacturer ?? sorted.compactMap(\.manufacturer).first,
                category: PluginCategory.guess(from: primary.name),
                installations: uniqueInstallations,
                artworkPath: nil
            ))
        }

        // Manual entries are also grouped by name and attached to the scanned card
        // whenever one exists, regardless of differences in vendor metadata.
        let manualGroups = Dictionary(grouping: manual) { normalize($0.name) }
        var manualOnly: [PluginProduct] = []

        for (nameKey, entries) in manualGroups {
            guard let first = entries.first else { continue }
            let formats = uniqueFormats(entries.map(\.format))
            if let index = scanned.firstIndex(where: { normalize($0.name) == nameKey }) {
                scanned[index].manualFormat = uniqueFormats(
                    [scanned[index].manualFormat].compactMap { $0 } + formats
                ).joined(separator: " · ")
                scanned[index].manualEntryIDs = entries.map(\.id)
                // A manually selected category is kept on this combined card.
                scanned[index].category = first.category
                if scanned[index].manufacturer?.isEmpty != false {
                    scanned[index].manufacturer = first.manufacturer
                }
            } else {
                manualOnly.append(PluginProduct(
                    id: "plugin:\(nameKey)",
                    name: first.name,
                    manufacturer: first.manufacturer,
                    category: first.category,
                    installations: [],
                    artworkPath: nil,
                    manualFormat: formats.joined(separator: " · "),
                    manualEntryIDs: entries.map(\.id)
                ))
            }
        }

        return (scanned + manualOnly).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func uniqueFormats(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.flatMap { $0.components(separatedBy: " · ") }.filter {
            let key = normalize($0)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    static func categoryOverrideKey(name: String, manufacturer: String?) -> String {
        // Key by product name alone so category corrections survive vendor metadata changes.
        normalize(name)
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        let alphanumeric = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return alphanumeric.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
