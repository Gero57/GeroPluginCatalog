import Foundation

struct PluginProduct: Identifiable, Hashable {
    /// Multiple formats can belong to the same product.
    let id: String
    var name: String
    var manufacturer: String?
    var category: PluginCategory
    var installations: [PluginInstallation]
    var artworkPath: String?
}
