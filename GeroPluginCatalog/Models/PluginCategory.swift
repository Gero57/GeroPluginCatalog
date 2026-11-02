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
    case drumPercussion = "Drum / Percussion"
    case bass = "Bass"
    case guitar = "Guitar"
    case sampler = "Sampler"
    case pianoKeys = "Piano / Keys"
    case orchestralStrings = "Orchestral / Strings"
    case instrument = "Other Instrument"
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
        case .synthesizer, .sampler, .instrument: return "pianokeys"
        case .drumPercussion: return "drum"
        case .bass, .guitar: return "guitars"
        case .pianoKeys: return "pianokeys"
        case .orchestralStrings: return "music.note"
        case .utility: return "wrench.and.screwdriver"
        case .other: return "puzzlepiece.extension"
        }
    }

    /// Best-effort name-based classification. Users can override it for manual entries.
    static func guess(from name: String) -> PluginCategory {
        let value = name.lowercased()

        // Effects first, so names such as "Bass Enhancer" are not mistaken for instruments.
        if contains(value, ["delay", "echo", "tape echo", "slap"]) { return .delay }
        if contains(value, ["reverb", "room", "plate", "hall", "spring", "space"]) { return .reverb }
        if contains(value, ["equalizer", "equaliser", "pro-q"]) || value.hasPrefix("eq ") || value.hasSuffix(" eq") {
            return .equalizer
        }
        if contains(value, ["limiter", "l2", "l3", "maximizer", "maximiser"]) { return .limiter }
        if contains(value, ["compressor", "comp", "1176", "la-2a", "bus comp"]) { return .compressor }
        if contains(value, ["chorus", "flanger", "phaser", "tremolo", "vibrato", "modulation"]) { return .modulation }
        if contains(value, ["distortion", "saturat", "overdrive", "fuzz", "amp", "crusher"]) { return .distortion }
        if contains(value, ["gate", "expander", "transient", "dynamics"]) { return .dynamics }
        if contains(value, ["meter", "tuner", "analyzer", "analyser", "utility", "gain"]) { return .utility }

        // Instrument families.
        if contains(value, ["drum", "percussion", "beat", "groove"]) { return .drumPercussion }
        if contains(value, ["bass", "sub bass", "upright bass"]) { return .bass }
        if contains(value, ["guitar", "amp sim", "guitar rig"]) { return .guitar }
        if contains(value, ["sampler", "sample player", "kontakt"]) { return .sampler }
        if contains(value, ["piano", "keys", "keyboard", "organ", "electric piano"]) { return .pianoKeys }
        if contains(value, ["orchestral", "strings", "violin", "cello", "ensemble", "symphony"]) {
            return .orchestralStrings
        }
        if contains(value, ["synth", "oscillator", "analog", "serum", "massive"]) { return .synthesizer }
        if contains(value, ["instrument", "player"]) { return .instrument }
        return .other
    }

    private static func contains(_ value: String, _ terms: [String]) -> Bool {
        terms.contains { value.localizedCaseInsensitiveContains($0) }
    }
}
