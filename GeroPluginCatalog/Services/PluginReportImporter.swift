import Foundation

struct PluginReportImporter {
    struct Result {
        let installations: [PluginInstallation]
        let effectCount: Int
        let instrumentCount: Int
    }

    func parse(_ text: String) -> Result {
        var section: PluginFormat?
        var installations: [PluginInstallation] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed == "VST3 Plug-ins" { section = .vst3; continue }
            if trimmed == "VST2 Plug-ins" { section = .vst2; continue }
            if trimmed == "Other Plug-ins" { section = .cubaseInternal; continue }
            if trimmed.isEmpty || trimmed.hasPrefix("Name ") || trimmed.hasPrefix("----") {
                continue
            }
            guard let format = section else { continue }

            // Split on repeated spaces while retaining paths that may themselves contain spaces.
            let columns = splitColumns(trimmed)
            guard columns.count >= 4, let path = columns.last, path.hasPrefix("/") else { continue }

            let name = columns[0]
            let vendor = columns.count > 1 ? columns[1] : ""
            let version = columns.count > 3 && !columns[3].isEmpty ? columns[3] : nil
            guard !name.isEmpty else { continue }

            installations.append(PluginInstallation(
                name: name,
                format: format,
                path: path,
                manufacturer: vendor.isEmpty ? nil : vendor,
                version: version,
                bundleIdentifier: nil,
                isUserInstalled: path.contains("/Users/")
            ))
        }

        let effects = installations.filter { $0.format != .cubaseInternal }.count
        let instruments = installations.count - effects
        return Result(installations: installations, effectCount: effects, instrumentCount: instruments)
    }

    private func splitColumns(_ line: String) -> [String] {
        // The final column is the full path; splitting only the leading metadata
        // columns avoids breaking paths containing spaces.
        let pattern = try! NSRegularExpression(pattern: #"\s{2,}"#)
        let ns = line as NSString
        let matches = pattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var fields: [String] = []
        var start = 0
        for match in matches {
            let value = ns.substring(with: NSRange(location: start, length: match.range.location - start))
                .trimmingCharacters(in: .whitespaces)
            if !value.isEmpty { fields.append(value) }
            start = NSRangeGetMaxRange(match.range)
        }
        let tail = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { fields.append(tail) }
        return fields
    }
}
