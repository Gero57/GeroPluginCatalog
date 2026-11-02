import Foundation

enum PluginCategory: String, CaseIterable, Identifiable, Codable {
    case delay = "Delay"
    case reverb = "Reverb"
    case equalizer = "Equalizer"
    case compressor = "Compressor"
    case limiter = "Limiter"
    case modulation = "Modulation"
    case distortion = "Distortion"
    case dynamics = "Dynamics"
    case synthesizer = "Synthesizer"
    case instrument = "Instrument"
    case utility = "Utility"
    case other = "Other"

    var id: String { rawValue }
}
