import Foundation

enum Role: String, Codable, CaseIterable, Identifiable {
    case t = "T"
    case r = "R"
    var id: String { rawValue }
    var title: String { rawValue }
    var other: Role { self == .t ? .r : .t }
}

struct FrameSet: Codable, Equatable {
    var squeeze: Double = 1
    var guide: String = "none"
    var clip: Bool = true
}

struct LightSet: Codable, Equatable {
    var program: String = "M"
    var iso: String = "400"
    var shutter: String = "1/250"
    var bulb: Bool = false
    var fstop: String = "8"
    var master: String = "T"
    var lockT: Bool = true
    var followCam: Bool = false
}

struct FocusSet: Codable, Equatable {
    var aid: String = "peaking"
    var color: String = "red"
    var level: String = "std"
}

struct LookSet: Equatable {
    var id: String = "standard"
    var base: String = "standard"
    var color: Int = 0
    var highlight: Int = 0
    var shadow: Int = 0
    var grain: String = "off"
    var filter: String = "none"
    /// A Core Image effect to try on the finished frame. Off leaves the stitch alone.
    var apple: String = "off"
}

extension LookSet: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, base, color, highlight, shadow, grain, filter, apple
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? "standard"
        base = try c.decodeIfPresent(String.self, forKey: .base) ?? "standard"
        color = try c.decodeIfPresent(Int.self, forKey: .color) ?? 0
        highlight = try c.decodeIfPresent(Int.self, forKey: .highlight) ?? 0
        shadow = try c.decodeIfPresent(Int.self, forKey: .shadow) ?? 0
        grain = try c.decodeIfPresent(String.self, forKey: .grain) ?? "off"
        filter = try c.decodeIfPresent(String.self, forKey: .filter) ?? "none"
        apple = try c.decodeIfPresent(String.self, forKey: .apple) ?? "off"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(base, forKey: .base)
        try c.encode(color, forKey: .color)
        try c.encode(highlight, forKey: .highlight)
        try c.encode(shadow, forKey: .shadow)
        try c.encode(grain, forKey: .grain)
        try c.encode(filter, forKey: .filter)
        try c.encode(apple, forKey: .apple)
    }
}

struct DriveSet: Equatable {
    /// USB is the release that ships. Sync is the 10-pin path, left for later.
    var release: String = "usb"
    var save: String = "ipad"
    var quality: String = "NEF+Fine"
    var timer: Int = 0
    var review: Int = 10
    var autoStitch: Bool = true
    var engine: String = "hugin"
    /// Develop the NEFs with CIRAW before the stitch. Off uses the camera JPEG.
    var ciraw: Bool = false
    /// Apple lens correction on the raw develop. Off keeps the overlap geometry already tuned.
    var cirawLens: Bool = false
}

extension DriveSet: Codable {
    private enum CodingKeys: String, CodingKey {
        case release, save, quality, timer, review, autoStitch, engine, ciraw, cirawLens
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        release = try c.decodeIfPresent(String.self, forKey: .release) ?? "usb"
        save = try c.decodeIfPresent(String.self, forKey: .save) ?? "ipad"
        quality = try c.decodeIfPresent(String.self, forKey: .quality) ?? "NEF+Fine"
        timer = try c.decodeIfPresent(Int.self, forKey: .timer) ?? 0
        review = try c.decodeIfPresent(Int.self, forKey: .review) ?? 10
        autoStitch = try c.decodeIfPresent(Bool.self, forKey: .autoStitch) ?? true
        engine = try c.decodeIfPresent(String.self, forKey: .engine) ?? "hugin"
        ciraw = try c.decodeIfPresent(Bool.self, forKey: .ciraw) ?? false
        cirawLens = try c.decodeIfPresent(Bool.self, forKey: .cirawLens) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(release, forKey: .release)
        try c.encode(save, forKey: .save)
        try c.encode(quality, forKey: .quality)
        try c.encode(timer, forKey: .timer)
        try c.encode(review, forKey: .review)
        try c.encode(autoStitch, forKey: .autoStitch)
        try c.encode(engine, forKey: .engine)
        try c.encode(ciraw, forKey: .ciraw)
        try c.encode(cirawLens, forKey: .cirawLens)
    }
}

struct Photo: Codable, Equatable {
    var frame = FrameSet()
    var light = LightSet()
    var focus = FocusSet()
    var look = LookSet()
    var drive = DriveSet()
    var wb: String = "Auto"

    var exposes: Bool { !light.followCam }
}

struct NamedMode: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var photo: Photo
}

struct Rig: Codable, Equatable {
    var overlap: Double = 0.20
    var flipR: Bool = true
    var balance: Bool = true
    var dy: Int = 0

    func overlap(width: Int, height: Int) -> Double {
        if abs(overlap - 0.20) < 0.0001 && width == 7360 && height == 4912 {
            return 0.22
        }
        return min(0.50, max(0.05, overlap))
    }
}

struct ShotNote: Equatable {
    var modeName: String = ""
    var look: String = ""
    var squeeze: Double = 1
    var styleBase: String = "standard"
    var styleGrain: String = "off"
    var styleFilter: String = "none"
    var styleApple: String = "off"
}

extension ShotNote: Codable {
    private enum CodingKeys: String, CodingKey {
        case modeName, look, squeeze, styleBase, styleGrain, styleFilter, styleApple
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modeName = try c.decodeIfPresent(String.self, forKey: .modeName) ?? ""
        look = try c.decodeIfPresent(String.self, forKey: .look) ?? ""
        squeeze = try c.decodeIfPresent(Double.self, forKey: .squeeze) ?? 1
        styleBase = try c.decodeIfPresent(String.self, forKey: .styleBase) ?? "standard"
        styleGrain = try c.decodeIfPresent(String.self, forKey: .styleGrain) ?? "off"
        styleFilter = try c.decodeIfPresent(String.self, forKey: .styleFilter) ?? "none"
        styleApple = try c.decodeIfPresent(String.self, forKey: .styleApple) ?? "off"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modeName, forKey: .modeName)
        try c.encode(look, forKey: .look)
        try c.encode(squeeze, forKey: .squeeze)
        try c.encode(styleBase, forKey: .styleBase)
        try c.encode(styleGrain, forKey: .styleGrain)
        try c.encode(styleFilter, forKey: .styleFilter)
        try c.encode(styleApple, forKey: .styleApple)
    }
}

enum Catalog {
    static let iso = ["Auto", "100", "125", "160", "200", "250", "320", "400", "500", "640",
                      "800", "1000", "1250", "1600", "2000", "2500", "3200", "4000", "5000", "6400", "12800", "25600"]
    static let shutter = ["Auto", "30", "20", "15", "10", "8", "6", "4", "3", "2", "1.6", "1.3", "1",
                          "0.8", "0.6", "0.5", "1/3", "1/4", "1/5", "1/6", "1/8", "1/10", "1/13", "1/15", "1/20", "1/25",
                          "1/30", "1/40", "1/50", "1/60", "1/80", "1/100", "1/125", "1/160", "1/200", "1/250", "1/320",
                          "1/400", "1/500", "1/640", "1/800", "1/1000", "1/1250", "1/1600", "1/2000", "1/2500", "1/3200",
                          "1/4000", "1/5000", "1/6400", "1/8000"]
    static let fstop = ["Auto", "1.4", "1.8", "2", "2.2", "2.5", "2.8", "3.2", "3.5", "4", "4.5",
                        "5", "5.6", "6.3", "7.1", "8", "9", "10", "11", "13", "14", "16", "18", "20", "22"]
    static let programs: [(String, String)] = [("M", "Manual"), ("A", "Aperture"), ("S", "Shutter"), ("P", "Program")]
    static let wb: [(String, String, Int)] = [
        ("Auto", "Auto", 0), ("Sunny", "Daylight", 5200), ("Cloudy", "Cloudy", 6000),
        ("Shade", "Shade", 8000), ("Tungsten", "Incandescent", 3000),
        ("Fluorescent", "Fluorescent", 4200), ("Flash", "Flash", 5400),
    ]
    static let quality: [(String, String, String)] = [
        ("NEF+Fine", "NEF + JPEG", "14-bit raw kept"),
        ("JPEG Fine", "JPEG Fine", "Smallest sets"),
        ("JPEG Normal", "JPEG Normal", ""),
        ("NEF (Raw)", "NEF only", "Stitch uses the preview"),
    ]
    static let formats: [(Double, String, String, String)] = [
        (1, "65:24", "Native", "2.71:1 · 65 MP"),
        (1.33, "3.6:1", "Anamorphic 1.33×", "86 MP"),
        (1.5, "4.07:1", "Anamorphic 1.5×", "98 MP"),
        (2, "5.42:1", "Anamorphic 2×", "130 MP"),
    ]
    static let guides: [(String, Double, String)] = [
        ("none", 0, "None"), ("3:1", 3, "3:1"), ("2.39", 2.39, "2.39:1"),
        ("2:1", 2, "2:1"), ("16:9", 16.0 / 9, "16:9"), ("4:3", 4.0 / 3, "4:3"),
    ]
    static let engines: [(String, String, String)] = [
        ("hugin", "Hugin", "SIFT similarity, multiband blend"),
        ("match", "Match", "Search overlap and dy"),
        ("blend", "Blend", "Fixed overlap, feathered"),
        ("cut", "Cut", "Fixed overlap, hard seam"),
    ]
    static let timers = [0, 2, 5, 10]
    static let reviews = [0, 3, 5, 10, 15]
    static let aids = ["off", "peaking", "loupe", "range"]
    static let peakColors: [(String, String, UInt32)] = [
        ("red", "Red", 0xFF3B30), ("yellow", "Yellow", 0xFFD60A),
        ("white", "White", 0xFFFFFF), ("blue", "Blue", 0x40A0FF),
    ]
    static let peakLevels = ["low", "std", "high"]
    static let nativeAspect = 2.712

    static func isAuto(_ v: String) -> Bool { v.trimmingCharacters(in: .whitespaces).lowercased() == "auto" }
    static func fmtISO(_ v: String) -> String { isAuto(v) ? "ISO Auto" : "ISO \(v)" }
    static func fmtShut(_ v: String) -> String {
        if isAuto(v) { return "Auto" }
        if v.range(of: #"^\d+(\.\d+)?$"#, options: .regularExpression) != nil { return v + "″" }
        return v
    }
    static func fmtF(_ v: String) -> String { isAuto(v) ? "Auto" : "f/" + v.replacingOccurrences(of: #"^f/?"#, with: "", options: .regularExpression) }
    static func format(_ squeeze: Double) -> (Double, String, String, String) {
        formats.min(by: { abs($0.0 - squeeze) < abs($1.0 - squeeze) }) ?? formats[0]
    }
    static func guide(_ id: String) -> (String, Double, String) {
        guides.first { $0.0 == id } ?? guides[0]
    }
    static func wbRow(_ id: String) -> (String, String, Int) {
        wb.first { $0.0 == id } ?? wb[0]
    }
    static func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

    static func step<T: Equatable>(_ values: [T], _ current: T, _ dir: Int) -> T {
        guard let i = values.firstIndex(of: current) else { return values.first ?? current }
        let j = min(values.count - 1, max(0, i + dir))
        return values[j]
    }

    /// Shutter as PTP ExposureTime units (1/10000 s). Nil for Auto.
    static func shutterTenThousandths(_ v: String) -> UInt32? {
        if isAuto(v) { return nil }
        if v.lowercased() == "bulb" { return 0xFFFF_FFFF }
        let slash = v.split(separator: "/").map(String.init)
        if slash.count == 2, let n = Double(slash[0]), let d = Double(slash[1]), d != 0 {
            return UInt32(max(1, (10_000.0 * n / d).rounded()))
        }
        if let sec = Double(v) {
            return UInt32(max(1, (sec * 10_000).rounded()))
        }
        return nil
    }

    static func fNumberHundredths(_ v: String) -> UInt16? {
        if isAuto(v) { return nil }
        let raw = v.replacingOccurrences(of: #"^f/?"#, with: "", options: .regularExpression)
        guard let n = Double(raw) else { return nil }
        return UInt16(max(1, (n * 100).rounded()))
    }

    static func isoValue(_ v: String) -> UInt16? {
        if isAuto(v) { return nil }
        return UInt16(v.filter(\.isNumber))
    }
}

enum LookBook {
    /// Output channel as weights of input red, green, and blue. This is the hue map a film simulation uses.
    struct Mix {
        var r: (Double, Double, Double)
        var g: (Double, Double, Double)
        var b: (Double, Double, Double)
    }

    struct Base {
        var sat: Double
        var curve: Double
        var gain: (Double, Double, Double)?
        var mix: Mix? = nil
        var mono: Bool
    }

    static let names: [(String, String, String)] = [
        ("standard", "Standard", "As shot"),
        ("apple", "Apple", "Local tone, vibrance, and a light sharpen"),
        ("neutral", "Neutral", "Flat, to grade"),
        ("vivid", "Vivid", "Saturated"),
        ("landscape", "Landscape", "Greens and blues"),
        ("chrome", "Chrome", "Muted slide, hard tone"),
        ("mono", "Mono", "Black and white"),
    ]

    /// The same kind of set a GFX body offers. Each one is a hue map and a tone curve, tuned to that stock.
    static let films: [(String, String, String)] = [
        ("provia", "Provia", "Standard slide. A little richer than as shot"),
        ("velvia", "Velvia", "Vivid slide. Deep greens and blues, hard tone"),
        ("astia", "Astia", "Soft slide. Holds skin, long highlights"),
        ("reala", "Reala", "Natural color negative. Slightly warm"),
        ("neghi", "Neg Hi", "Portrait negative, a bit of contrast"),
        ("negstd", "Neg Std", "Portrait negative, flatter"),
        ("classicneg", "Classic Neg", "Consumer negative. Warm, a little green"),
        ("nostalgic", "Nostalgic", "Amber highlights, faded shadows"),
        ("eterna", "Eterna", "Cinema. Flat, quiet color"),
        ("bleach", "Bleach", "Flat color, steep tone"),
        ("acros", "Acros", "Hard black and white"),
    ]
    static let filters = ["none", "yellow", "orange", "red", "green"]
    static let grains = ["off", "weak", "strong"]

    /// Off, or a second tap on the active film, returns to Standard.
    static func pickFilm(_ current: String, _ value: String) -> String {
        let on = films.contains { $0.0 == current }
        if value == "off" || (on && value == current) { return on ? "standard" : current }
        return value
    }
    static let steps = [-4, -3, -2, -1, 0, 1, 2, 3, 4]

    static func base(_ id: String) -> Base {
        switch id {
        case "neutral": return Base(sat: 0.86, curve: -1.5, gain: nil, mono: false)
        case "vivid": return Base(sat: 1.35, curve: 1.5, gain: nil, mono: false)
        case "landscape": return Base(sat: 1.18, curve: 1, gain: (1, 1.05, 1.06), mono: false)
        case "chrome": return Base(sat: 0.76, curve: 2.2, gain: nil, mix: Mix(
            r: (0.98, 0.03, -0.02), g: (-0.03, 0.96, 0.04), b: (-0.04, 0.08, 1.04)
        ), mono: false)
        case "mono": return Base(sat: 0, curve: 1.2, gain: nil, mono: true)
        case "apple": return Base(sat: 1, curve: 0, gain: nil, mono: false)
        case "provia": return Base(sat: 1.08, curve: 0.8, gain: nil, mix: Mix(
            r: (1.02, 0.00, -0.01), g: (-0.01, 1.05, -0.01), b: (-0.01, 0.00, 1.05)
        ), mono: false)
        case "velvia": return Base(sat: 1.22, curve: 2.4, gain: nil, mix: Mix(
            r: (1.22, -0.14, 0.02), g: (-0.04, 1.30, -0.12), b: (-0.06, -0.16, 1.30)
        ), mono: false)
        case "astia": return Base(sat: 0.94, curve: -0.9, gain: nil, mix: Mix(
            r: (1.06, 0.03, 0.00), g: (0.01, 0.98, 0.00), b: (0.00, 0.02, 0.90)
        ), mono: false)
        case "reala": return Base(sat: 1.05, curve: 0.4, gain: nil, mix: Mix(
            r: (1.05, 0.01, 0.00), g: (0.00, 1.02, 0.00), b: (0.00, 0.02, 0.95)
        ), mono: false)
        case "neghi": return Base(sat: 0.92, curve: 1.1, gain: nil, mix: Mix(
            r: (1.06, 0.01, 0.00), g: (0.00, 1.00, 0.00), b: (0.00, 0.02, 0.93)
        ), mono: false)
        case "negstd": return Base(sat: 0.86, curve: -0.7, gain: nil, mix: Mix(
            r: (1.04, 0.02, 0.00), g: (0.01, 0.99, 0.00), b: (0.00, 0.02, 0.94)
        ), mono: false)
        case "classicneg": return Base(sat: 0.90, curve: -0.3, gain: nil, mix: Mix(
            r: (1.12, 0.02, -0.02), g: (0.05, 1.02, 0.00), b: (0.00, 0.07, 0.86)
        ), mono: false)
        case "nostalgic": return Base(sat: 1.08, curve: -0.5, gain: nil, mix: Mix(
            r: (1.16, 0.04, 0.00), g: (0.02, 1.00, 0.00), b: (-0.02, 0.03, 0.80)
        ), mono: false)
        case "eterna": return Base(sat: 0.70, curve: -2.4, gain: nil, mix: Mix(
            r: (0.98, 0.02, 0.00), g: (0.01, 1.00, 0.02), b: (0.00, 0.04, 1.02)
        ), mono: false)
        case "bleach": return Base(sat: 0.55, curve: 2.8, gain: nil, mix: Mix(
            r: (0.96, 0.02, 0.00), g: (0.00, 0.98, 0.03), b: (0.00, 0.05, 1.08)
        ), mono: false)
        case "acros": return Base(sat: 0, curve: 1.8, gain: nil, mono: true)
        default: return Base(sat: 1, curve: 0, gain: nil, mono: false)
        }
    }

    static func mix(_ filter: String) -> (Double, Double, Double) {
        switch filter {
        case "yellow": return (0.40, 0.50, 0.10)
        case "orange": return (0.50, 0.40, 0.10)
        case "red": return (0.66, 0.30, 0.04)
        case "green": return (0.22, 0.66, 0.12)
        default: return (0.30, 0.59, 0.11)
        }
    }

    static func amounts(_ look: LookSet) -> (Double, Double) {
        let b = base(look.base)
        let s = min(5, max(-5, b.curve + Double(look.shadow)))
        let h = min(5, max(-5, b.curve + Double(look.highlight)))
        return (s, h)
    }

    static func curve(_ x: Double, shadow: Double, high: Double) -> Double {
        let k = x < 0.5 ? shadow : high
        return min(1, max(0, x - k * 0.03 * sin(2 * .pi * x)))
    }

    static func isMono(_ look: LookSet) -> Bool { base(look.base).mono }

    static func name(_ look: LookSet) -> String {
        (names + films).first { $0.0 == look.base }?.1 ?? "Standard"
    }

    static func savedTitle(_ look: LookSet) -> String {
        var bits = [name(look)]
        if isMono(look), look.filter != "none" {
            bits.append(look.filter.prefix(1).uppercased() + look.filter.dropFirst())
        }
        if look.grain != "off" { bits.append(look.grain) }
        if !look.apple.isEmpty, look.apple != "off" { bits.append(AppleBook.title(look.apple)) }
        return bits.joined(separator: " · ")
    }

    static func note(_ look: LookSet) -> String {
        (names + films).first { $0.0 == look.base }?.2 ?? ""
    }

    static func tweaks(_ look: LookSet) -> [String] {
        var bits: [String] = []
        if !isMono(look), look.color != 0 { bits.append("Color \(Catalog.signed(look.color))") }
        if look.highlight != 0 { bits.append("Highlight \(Catalog.signed(look.highlight))") }
        if look.shadow != 0 { bits.append("Shadow \(Catalog.signed(look.shadow))") }
        if isMono(look), look.filter != "none" {
            bits.append(look.filter.prefix(1).uppercased() + look.filter.dropFirst() + " filter")
        }
        if look.grain != "off" { bits.append("Grain \(look.grain)") }
        return bits
    }

    static func identity(_ look: LookSet) -> Bool {
        if look.base == "apple" { return false }
        let b = base(look.base)
        return !b.mono && abs(b.sat - 1) < 0.01 && b.gain == nil && b.mix == nil && b.curve == 0
            && look.color == 0 && look.highlight == 0 && look.shadow == 0 && look.grain == "off"
            && (look.apple.isEmpty || look.apple == "off")
    }
}

/// Still-image tools in this SDK that can run on a finished Nikon JPEG.
enum AppleBook {
    struct Group: Identifiable, Equatable {
        var id: String
        var title: String
        var viewer: String
    }

    struct Effect: Identifiable, Equatable {
        var id: String
        var title: String
        var detail: String
        var filter: String
        var group: String
    }

    static let groups: [Group] = [
        Group(id: "effect", title: "Photo effects", viewer: "Apple photo effect"),
        Group(id: "color", title: "Color", viewer: "Apple color"),
        Group(id: "finish", title: "Finish", viewer: "Apple finish"),
        Group(id: "vision", title: "Vision", viewer: "Vision"),
    ]

    static let effects: [Effect] = [
        Effect(id: "mono", title: "Mono", detail: "Black and white", filter: "CIPhotoEffectMono", group: "effect"),
        Effect(id: "noir", title: "Noir", detail: "Hard black and white", filter: "CIPhotoEffectNoir", group: "effect"),
        Effect(id: "chrome", title: "Chrome", detail: "Cool, contrasty color", filter: "CIPhotoEffectChrome", group: "effect"),
        Effect(id: "fade", title: "Fade", detail: "Lifted blacks", filter: "CIPhotoEffectFade", group: "effect"),
        Effect(id: "instant", title: "Instant", detail: "Instant-film color", filter: "CIPhotoEffectInstant", group: "effect"),
        Effect(id: "process", title: "Process", detail: "Cross-process color", filter: "CIPhotoEffectProcess", group: "effect"),
        Effect(id: "tonal", title: "Tonal", detail: "Flat black and white", filter: "CIPhotoEffectTonal", group: "effect"),
        Effect(id: "transfer", title: "Transfer", detail: "Warm and faded", filter: "CIPhotoEffectTransfer", group: "effect"),
        Effect(id: "vibrance", title: "Vibrance", detail: "Color that holds skin tones", filter: "CIVibrance", group: "color"),
        Effect(id: "warm", title: "Warm", detail: "Shift the white point warmer", filter: "CITemperatureAndTint", group: "color"),
        Effect(id: "cool", title: "Cool", detail: "Shift the white point cooler", filter: "CITemperatureAndTint", group: "color"),
        Effect(id: "sharpen", title: "Sharpen", detail: "Luminance sharpen", filter: "CISharpenLuminance", group: "finish"),
        Effect(id: "unsharp", title: "Unsharp", detail: "Stronger edge contrast", filter: "CIUnsharpMask", group: "finish"),
        Effect(id: "denoise", title: "Denoise", detail: "Smooth noise, keep edges", filter: "CINoiseReduction", group: "finish"),
        Effect(id: "bloom", title: "Bloom", detail: "Glow on the bright edges", filter: "CIBloom", group: "finish"),
        Effect(id: "vignette", title: "Vignette", detail: "Darken the corners", filter: "CIVignette", group: "finish"),
        Effect(id: "recover", title: "Recover", detail: "Pull highlights, open shadows", filter: "CIHighlightShadowAdjust", group: "finish"),
        Effect(id: "subject", title: "Subject", detail: "Keep what Vision can lift, darken the rest", filter: "VNGenerateForegroundInstanceMaskRequest", group: "vision"),
        Effect(id: "people", title: "People", detail: "Same lift, people only", filter: "VNGeneratePersonInstanceMaskRequest", group: "vision"),
    ]

    static let defaultOn: [String] = effects.map(\.id)

    static func effect(_ id: String) -> Effect? {
        effects.first { $0.id == id }
    }

    static func title(_ id: String) -> String {
        effect(id)?.title ?? ""
    }

    /// Off, plus the effects this group is allowed to show. The current pick stays listed so it can be turned off.
    static func options(_ enabled: [String], group: String, current: String) -> [(String, String)] {
        let rows = effects.filter { $0.group == group && (enabled.contains($0.id) || $0.id == current) }
        if rows.isEmpty { return [] }
        return [("off", "Off")] + rows.map { ($0.id, $0.title) }
    }
}

enum Seed {
    static func modes() -> [NamedMode] {
        var landscape = Photo()
        landscape.light.iso = "200"
        landscape.light.shutter = "1/250"
        landscape.light.fstop = "8"
        landscape.look.base = "landscape"
        landscape.look.id = "landscape"

        var street = Photo()
        street.light.iso = "800"
        street.light.shutter = "1/250"
        street.light.fstop = "5.6"
        street.look.base = "chrome"
        street.look.id = "chrome"

        var ana = Photo()
        ana.frame.squeeze = 2
        ana.light.iso = "400"
        ana.light.shutter = "1/125"
        ana.look.base = "vivid"
        ana.look.id = "vivid"

        var mono = Photo()
        mono.look.base = "mono"
        mono.look.id = "mono"
        mono.look.filter = "yellow"
        mono.light.iso = "400"
        mono.light.shutter = "1/250"

        var bench = Photo()
        bench.light.iso = "100"
        bench.light.shutter = "1/60"
        bench.light.fstop = "8"
        bench.drive.engine = "blend"
        bench.drive.timer = 2

        return [
            appleMode(),
            NamedMode(id: "landscape", name: "Landscape", photo: landscape),
            NamedMode(id: "street", name: "Street", photo: street),
            NamedMode(id: "ana2", name: "Ana 2×", photo: ana),
            NamedMode(id: "mono", name: "Mono", photo: mono),
            NamedMode(id: "bench", name: "Bench", photo: bench),
        ]
    }

    /// CIRAW local tone when a NEF is present, then vibrance and a light sharpen on the panorama.
    static func appleMode() -> NamedMode {
        var photo = Photo()
        photo.light.iso = "100"
        photo.light.shutter = "1/250"
        photo.light.fstop = "8"
        photo.look.base = "apple"
        photo.look.id = "apple"
        photo.drive.quality = "NEF+Fine"
        photo.drive.engine = "hugin"
        photo.drive.ciraw = true
        photo.wb = "Auto"
        return NamedMode(id: "apple", name: "Apple", photo: photo)
    }
}
