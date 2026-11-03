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
    var manualEntryIDs: [String] = []

    static func catalog(from installations: [PluginInstallation], manual: [ManualPlugin] = []) -> [PluginProduct] {
        // First group by the normalized plug-in name. Manufacturer metadata is
        // sometimes missing or spelled differently between AU and VST bundles.
        let byName = Dictionary(grouping: installations) { normalize($0.name) }
        var scanned: [PluginProduct] = []

        for (_, sameNameItems) in byName {
            let knownMakers = Set(sameNameItems.compactMap { item -> String? in
                let maker = normalize(item.manufacturer ?? "")
                return maker.isEmpty ? nil : maker
            })

            // If there is only one known manufacturer, merge entries with missing
            // manufacturer metadata into that product. If multiple makers use the
            // same plug-in name, keep them as separate products.
            let makerGroups: [[PluginInstallation]]
            if knownMakers.count <= 1 {
                makerGroups = [sameNameItems]
            } else {
                makerGroups = Array(Dictionary(grouping: sameNameItems) {
                    normalize($0.manufacturer ?? "")
                }.values)
            }

            for items in makerGroups {
                let sorted = items.sorted { $0.format.rawValue < $1.format.rawValue }
                guard let primary = sorted.first else { continue }
                let normalizedName = normalize(primary.name)
                let preferred = items.first(where: { $0.format == .vst3 && !($0.bundleIdentifier ?? "").isEmpty })
                    ?? items.first(where: { !($0.bundleIdentifier ?? "").isEmpty })
                let productID: String
                if let bundleID = preferred?.bundleIdentifier {
                    productID = "bundle:\(bundleID.lowercased())|class:\(normalizedName)"
                } else {
                    productID = "name:\(normalize(primary.manufacturer ?? ""))|\(normalizedName)"
                }

                scanned.append(PluginProduct(
                    id: productID,
                    name: primary.name,
                    manufacturer: sorted.compactMap(\.manufacturer).first,
                    category: PluginCategory.guess(from: primary.name),
                    installations: sorted,
                    artworkPath: nil
                ))
            }
        }

        // Collapse duplicate manual records (e.g. Roomworks / RoomWorks) and
        // attach them to a scanned product when the identity is unambiguous.
        let manualGroups = Dictionary(grouping: manual) {
            "\(normalize($0.manufacturer))|\(normalize($0.name))"
        }
        var manualOnly: [PluginProduct] = []

        for (_, entries) in manualGroups {
            guard let first = entries.first else { continue }
            let formats = uniqueFormats(entries.map(\.format))
            let nameKey = normalize(first.name)
            let makerKey = normalize(first.manufacturer)
            let candidates = scanned.indices.filter { index in
                guard normalize(scanned[index].name) == nameKey else { return false }
                let scannedMaker = normalize(scanned[index].manufacturer ?? "")
                return makerKey.isEmpty || scannedMaker.isEmpty || scannedMaker == makerKey
            }

            if candidates.count == 1, let index = candidates.first {
                scanned[index].manualFormat = uniqueFormats(
                    [scanned[index].manualFormat].compactMap { $0 } + formats
                ).joined(separator: " · ")
                scanned[index].manualEntryIDs = entries.map(\.id)
                scanned[index].category = first.category
            } else {
                manualOnly.append(PluginProduct(
                    id: first.id,
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

        // Final safety pass: collapse products whose display names and vendors
        // normalize to the same identity. This catches duplicated bundle records
        // and metadata differences that slipped through the first grouping pass.
        var deduplicated: [PluginProduct] = []
        for product in scanned {
            let nameKey = normalize(product.name)
            let makerKey = normalize(product.manufacturer ?? "")
            if let index = deduplicated.firstIndex(where: {
                normalize($0.name) == nameKey &&
                (normalize($0.manufacturer ?? "").isEmpty || makerKey.isEmpty ||
                 normalize($0.manufacturer ?? "") == makerKey)
            }) {
                deduplicated[index].installations = Array(Set(
                    deduplicated[index].installations + product.installations
                )).sorted { $0.format.rawValue < $1.format.rawValue }
                if deduplicated[index].manufacturer?.isEmpty != false {
                    deduplicated[index].manufacturer = product.manufacturer
                }
                if deduplicated[index].artworkPath == nil {
                    deduplicated[index].artworkPath = product.artworkPath
                }
            } else {
                deduplicated.append(product)
            }
        }

        return (deduplicated + manualOnly).sorted {
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
        "\(normalize(manufacturer ?? ""))|\(normalize(name))"
    }

    private static func normalize(_ value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: .current)
        let alphanumeric = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }.joined()
        return alphanumeric.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}
