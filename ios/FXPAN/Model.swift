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

struct LookSet: Codable, Equatable {
    var id: String = "standard"
    var base: String = "standard"
    var color: Int = 0
    var highlight: Int = 0
    var shadow: Int = 0
    var grain: String = "off"
    var filter: String = "none"
}

struct DriveSet: Codable, Equatable {
    /// USB is the release that ships. Sync is the 10-pin path, left for later.
    var release: String = "usb"
    var save: String = "ipad"
    var quality: String = "NEF+Fine"
    var timer: Int = 0
    var review: Int = 10
    var autoStitch: Bool = true
    var engine: String = "match"
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

struct ShotNote: Codable, Equatable {
    var modeName: String = ""
    var look: String = ""
    var squeeze: Double = 1
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
        ("match", "Match", "Search overlap and dy"),
        ("blend", "Blend", "Fixed overlap, feathered"),
        ("cut", "Cut", "Fixed overlap, hard seam"),
    ]
    static let timers = [0, 2, 5, 10]
    static let reviews = [0, 3, 5, 10, 15]
    static let aids = ["off", "peaking", "loupe"]
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
    struct Base {
        var sat: Double
        var curve: Double
        var gain: (Double, Double, Double)?
        var mono: Bool
    }

    static let names: [(String, String, String)] = [
        ("standard", "Standard", "As shot"),
        ("neutral", "Neutral", "Flat, to grade"),
        ("vivid", "Vivid", "Saturated"),
        ("landscape", "Landscape", "Greens and blues"),
        ("chrome", "Chrome", "Muted, hard tone"),
        ("mono", "Mono", "Black and white"),
    ]
    static let filters = ["none", "yellow", "orange", "red", "green"]
    static let grains = ["off", "weak", "strong"]
    static let steps = [-4, -3, -2, -1, 0, 1, 2, 3, 4]

    static func base(_ id: String) -> Base {
        switch id {
        case "neutral": return Base(sat: 0.86, curve: -1.5, gain: nil, mono: false)
        case "vivid": return Base(sat: 1.35, curve: 1.5, gain: nil, mono: false)
        case "landscape": return Base(sat: 1.18, curve: 1, gain: (1, 1.05, 1.06), mono: false)
        case "chrome": return Base(sat: 0.78, curve: 2.2, gain: nil, mono: false)
        case "mono": return Base(sat: 0, curve: 1.2, gain: nil, mono: true)
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
        names.first { $0.0 == look.base }?.1 ?? "Standard"
    }

    static func note(_ look: LookSet) -> String {
        names.first { $0.0 == look.base }?.2 ?? ""
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
        let b = base(look.base)
        return !b.mono && abs(b.sat - 1) < 0.01 && b.gain == nil && b.curve == 0
            && look.color == 0 && look.highlight == 0 && look.shadow == 0 && look.grain == "off"
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
            NamedMode(id: "landscape", name: "Landscape", photo: landscape),
            NamedMode(id: "street", name: "Street", photo: street),
            NamedMode(id: "ana2", name: "Ana 2×", photo: ana),
            NamedMode(id: "mono", name: "Mono", photo: mono),
            NamedMode(id: "bench", name: "Bench", photo: bench),
        ]
    }
}
