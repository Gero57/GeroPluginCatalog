import Foundation
import AudioToolbox

struct PluginScanner {
    struct ScanResult {
        let installations: [PluginInstallation]
        let inaccessibleFolders: [String]
    }

    private let fileManager = FileManager.default

    private struct ScanRoot {
        let url: URL
        let format: PluginFormat
        let isUser: Bool
    }

    func scan() -> ScanResult {
        let roots = makeRoots()
        var found: [PluginInstallation] = []
        var inaccessible: [String] = []

        for root in roots {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: root.url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }

            scanDirectory(root.url, format: root.format, isUser: root.isUser,
                          found: &found, inaccessible: &inaccessible)
        }

        let unique = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScanResult(
            installations: unique.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            inaccessibleFolders: inaccessible
        )
    }

    /// Reads standard plug-in folders plus Cubase/Nuendo application-local and
    /// Steinberg shared component bundles. No plug-in binary is loaded or executed.
    private func scanDirectory(
        _ directory: URL, format: PluginFormat, isUser: Bool,
        found: inout [PluginInstallation], inaccessible: inout [String]
    ) {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            inaccessible.append(directory.path)
            return
        }

        while let entry = enumerator.nextObject() as? URL {
            guard entry.pathExtension.caseInsensitiveCompare(format.fileExtension) == .orderedSame else {
                continue
            }
            found.append(contentsOf: inspectBundle(at: entry, format: format, isUser: isUser))
            enumerator.skipDescendants()
        }
    }

    private func makeRoots() -> [ScanRoot] {
        let systemBase = URL(fileURLWithPath: "/Library/Audio/Plug-Ins", isDirectory: true)
        let userBase = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Audio/Plug-Ins", isDirectory: true)

        var roots = PluginFormat.allCases.filter { $0 != .cubaseInternal }.flatMap { format in
            [
                ScanRoot(url: systemBase.appendingPathComponent(format.folderName, isDirectory: true),
                         format: format, isUser: false),
                ScanRoot(url: userBase.appendingPathComponent(format.folderName, isDirectory: true),
                         format: format, isUser: true)
            ]
        }

        // Steinberg shared components used by Cubase, including Cubase's own
        // internal processors and instruments.
        roots.append(ScanRoot(
            url: URL(fileURLWithPath: "/Library/Application Support/Steinberg/Components", isDirectory: true),
            format: .cubaseInternal, isUser: false
        ))
        roots.append(ScanRoot(
            url: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Steinberg/Components", isDirectory: true),
            format: .cubaseInternal, isUser: true
        ))

        let applicationFolders = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Steinberg", isDirectory: true)
        ]

        for folder in applicationFolders {
            guard let entries = try? fileManager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for app in entries where app.pathExtension.lowercased() == "app" {
                let appName = app.deletingPathExtension().lastPathComponent.lowercased()
                guard appName.contains("cubase") || appName.contains("nuendo") else { continue }

                let contents = app.appendingPathComponent("Contents", isDirectory: true)
                roots.append(ScanRoot(
                    url: contents.appendingPathComponent("VST3", isDirectory: true),
                    format: .vst3, isUser: false
                ))
                roots.append(ScanRoot(
                    url: contents.appendingPathComponent("VstPlugins", isDirectory: true),
                    format: .vst2, isUser: false
                ))
                roots.append(ScanRoot(
                    url: contents.appendingPathComponent("Components", isDirectory: true),
                    format: .cubaseInternal, isUser: false
                ))
            }
        }
        return roots
    }

    private func inspectBundle(at url: URL, format: PluginFormat, isUser: Bool) -> [PluginInstallation] {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]
        let fallbackName = nonEmptyString(info["CFBundleDisplayName"])
            ?? nonEmptyString(info["CFBundleName"])
            ?? url.deletingPathExtension().lastPathComponent
        let fallbackManufacturer = nonEmptyString(info["manufacturer"])
        let version = nonEmptyString(info["CFBundleShortVersionString"])
            ?? nonEmptyString(info["CFBundleVersion"])
        let bundleIdentifier = bundle?.bundleIdentifier

        if format == .vst3,
           let audioClasses = readVST3AudioClasses(in: url),
           !audioClasses.isEmpty {
            return audioClasses.map { item in
                PluginInstallation(
                    name: item.name, format: format, path: url.path,
                    manufacturer: item.manufacturer ?? fallbackManufacturer,
                    version: version, bundleIdentifier: bundleIdentifier,
                    isUserInstalled: isUser
                )
            }
        }

        let audioComponents = info["AudioComponents"] as? [[String: Any]]
        let manufacturer = nonEmptyString(audioComponents?.first?["manufacturer"])
            ?? fallbackManufacturer

        return [PluginInstallation(
            name: fallbackName, format: format, path: url.path,
            manufacturer: manufacturer, version: version,
            bundleIdentifier: bundleIdentifier, isUserInstalled: isUser
        )]
    }

    private func readVST3AudioClasses(in bundleURL: URL) -> [(name: String, manufacturer: String?)]? {
        let candidates = [
            bundleURL.appendingPathComponent("Contents/Resources/moduleinfo.json"),
            bundleURL.appendingPathComponent("Contents/moduleinfo.json")
        ]
        guard let moduleURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }),
              let data = try? Data(contentsOf: moduleURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let classes = root["Classes"] as? [[String: Any]] else { return nil }

        let result = classes.compactMap { item -> (name: String, manufacturer: String?)? in
            let category = nonEmptyString(item["Category"])?.lowercased() ?? ""
            guard category.contains("audio module"),
                  let name = nonEmptyString(item["Name"]) else { return nil }
            return (name, nonEmptyString(item["Vendor"]))
        }
        return result.isEmpty ? nil : result
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
