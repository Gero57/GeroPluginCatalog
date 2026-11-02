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
                  isDirectory.boolValue else {
                continue
            }

            scanDirectory(
                root.url,
                format: root.format,
                isUser: root.isUser,
                found: &found,
                inaccessible: &inaccessible
            )
        }

        let unique = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScanResult(
            installations: unique.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            inaccessibleFolders: inaccessible
        )
    }

    /// Searches vendor subfolders, but treats each plug-in bundle as one unit.
    private func scanDirectory(
        _ directory: URL,
        format: PluginFormat,
        isUser: Bool,
        found: inout [PluginInstallation],
        inaccessible: inout [String]
    ) {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            inaccessible.append(directory.path)
            return
        }

        let expectedExtension = format.fileExtension.lowercased()

        for entry in entries {
            if entry.pathExtension.lowercased() == expectedExtension {
                if let installation = inspectBundle(at: entry, format: format, isUser: isUser) {
                    found.append(installation)
                }
                // Never descend into a plug-in package's internal contents.
                continue
            }

            do {
                let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                if values.isDirectory == true && values.isPackage != true {
                    scanDirectory(
                        entry,
                        format: format,
                        isUser: isUser,
                        found: &found,
                        inaccessible: &inaccessible
                    )
                }
            } catch {
                inaccessible.append(entry.path)
            }
        }
    }

    private func makeRoots() -> [ScanRoot] {
        let systemBase = URL(fileURLWithPath: "/Library/Audio/Plug-Ins", isDirectory: true)
        let userBase = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Audio/Plug-Ins", isDirectory: true)

        return PluginFormat.allCases.flatMap { format in
            [
                ScanRoot(url: systemBase.appendingPathComponent(format.folderName, isDirectory: true),
                         format: format, isUser: false),
                ScanRoot(url: userBase.appendingPathComponent(format.folderName, isDirectory: true),
                         format: format, isUser: true)
            ]
        }
    }

    private func inspectBundle(at url: URL, format: PluginFormat, isUser: Bool) -> PluginInstallation? {
        let bundle = Bundle(url: url)
        let info = bundle?.infoDictionary ?? [:]

        // Some vendors ship bundle metadata with empty display-name fields.
        // Treat empty/whitespace-only values as missing and use the bundle filename.
        let displayName = nonEmptyString(info["CFBundleDisplayName"])
            ?? nonEmptyString(info["CFBundleName"])
            ?? url.deletingPathExtension().lastPathComponent

        let audioComponents = info["AudioComponents"] as? [[String: Any]]
        let manufacturer = nonEmptyString(audioComponents?.first?["manufacturer"])
            ?? nonEmptyString(info["manufacturer"])

        let version = nonEmptyString(info["CFBundleShortVersionString"])
            ?? nonEmptyString(info["CFBundleVersion"])

        return PluginInstallation(
            name: displayName,
            format: format,
            path: url.path,
            manufacturer: manufacturer,
            version: version,
            bundleIdentifier: bundle?.bundleIdentifier,
            isUserInstalled: isUser
        )
    }

    private func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
