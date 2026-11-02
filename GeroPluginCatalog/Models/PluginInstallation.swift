import Foundation

struct PluginInstallation: Identifiable, Hashable, Codable {
    /// Stable identity for this particular installed format/location.
    var id: String { "\(format.rawValue)|\(path)" }

    let name: String
    let format: PluginFormat
    let path: String
    let manufacturer: String?
    let version: String?
    let bundleIdentifier: String?
    let isUserInstalled: Bool
}
