import Foundation

struct PluginInstallation: Identifiable, Hashable, Codable {
    /// Stable identity for a plug-in class in a particular format/location.
    /// One VST3 bundle can expose multiple audio plug-in classes.
    var id: String { "\(format.rawValue)|\(path)|\(name)" }

    let name: String
    let format: PluginFormat
    let path: String
    let manufacturer: String?
    let version: String?
    let bundleIdentifier: String?
    let isUserInstalled: Bool
}
