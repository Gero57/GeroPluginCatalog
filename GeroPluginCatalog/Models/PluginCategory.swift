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

    var symbol: String {
        switch self {
        case .delay: return "arrow.left.arrow.right"
        case .reverb: return "water.waves"
        case .equalizer: return "slider.horizontal.3"
        case .compressor, .limiter, .dynamics: return "waveform.path"
        case .modulation: return "waveform"
        case .distortion: return "bolt"
        case .synthesizer, .instrument: return "pianokeys"
        case .utility: return "wrench.and.screwdriver"
        case .other: return "puzzlepiece.extension"
        }
    }

    /// Conservative name-based guess; users can refine categories in a later phase.
    static func guess(from name: String) -> PluginCategory {
        let value = name.lowercased()
        if contains(value, ["delay", "echo", "tape echo", "slap"]) { return .delay }
        if contains(value, ["reverb", "room", "plate", "hall", "spring", "space"]) { return .reverb }
        if contains(value, ["equalizer", "equaliser", "\beq\b", "pro-q"]) { return .equalizer }
        if contains(value, ["limiter", "l2", "l3", "maximizer", "maximiser"]) { return .limiter }
        if contains(value, ["compressor", "comp", "1176", "la-2a", "bus comp"]) { return .compressor }
        if contains(value, ["chorus", "flanger", "phaser", "tremolo", "vibrato", "modulation"]) { return .modulation }
        if contains(value, ["distortion", "saturat", "overdrive", "fuzz", "amp", "crusher"]) { return .distortion }
        if contains(value, ["synth", "oscillator", "analog", "serum", "massive"]) { return .synthesizer }
        if contains(value, ["piano", "organ", "strings", "drum", "kontakt", "instrument", "player"]) { return .instrument }
        if contains(value, ["meter", "tuner", "analyzer", "analyser", "utility", "gain"]) { return .utility }
        if contains(value, ["gate", "expander", "transient", "dynamics"]) { return .dynamics }
        return .other
    }

    private static func contains(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.localizedCaseInsensitiveContains($0) }
    }
}
