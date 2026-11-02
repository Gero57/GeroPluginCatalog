import Foundation

struct ManualPlugin: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var manufacturer: String
    var category: PluginCategory
    var format: String

    init(id: String = "manual:\(UUID().uuidString)", name: String, manufacturer: String,
         category: PluginCategory, format: String) {
        self.id = id
        self.name = name
        self.manufacturer = manufacturer
        self.category = category
        self.format = format
    }
}
