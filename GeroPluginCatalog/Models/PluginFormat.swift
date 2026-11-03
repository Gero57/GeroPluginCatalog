import Foundation

enum PluginFormat: String, CaseIterable, Codable, Identifiable {
    case vst2 = "VST2"
    case vst3 = "VST3"
    case audioUnit = "AU"
    case cubaseInternal = "Cubase Internal"

    var id: String { rawValue }

    var folderName: String {
        switch self {
        case .vst2: return "VST"
        case .vst3: return "VST3"
        case .audioUnit: return "Components"
        case .cubaseInternal: return "Components"
        }
    }

    var fileExtension: String {
        switch self {
        case .vst2: return "vst"
        case .vst3: return "vst3"
        case .audioUnit: return "component"
        case .cubaseInternal: return "component"
        }
    }
}
