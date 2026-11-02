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

            do {
                let entries = try fileManager.contentsOfDirectory(
                    at: root.url,
                    includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
                    options: [.skipsHiddenFiles]
                )

                for entry in entries where entry.pathExtension.lowercased() == root.format.fileExtension.lowercased() {
                    guard let installation = inspectBundle(
                        at: entry,
                        format: root.format,
                        isUser: root.isUser
                    ) else { continue }
                    found.append(installation)
                }
            } catch {
                inaccessible.append(root.url.path)
            }
        }

        let unique = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ScanResult(
            installations: unique.values.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            },
            inaccessibleFolders: inaccessible
        )
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

        let displayName = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let manufacturer = (info["AudioComponents"] as? [[String: Any]])?
            .first?["manufacturer"] as? String
            ?? info["manufacturer"] as? String

        let version = (info["CFBundleShortVersionString"] as? String)
            ?? (info["CFBundleVersion"] as? String)

        let bundleIdentifier = bundle?.bundleIdentifier

        return PluginInstallation(
            name: displayName,
            format: format,
            path: url.path,
            manufacturer: manufacturer,
            version: version,
            bundleIdentifier: bundleIdentifier,
            isUserInstalled: isUser
        )
    }
}
