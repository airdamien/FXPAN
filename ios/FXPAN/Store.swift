import Foundation

struct Persisted: Codable {
    var photo = Photo()
    var modes: [NamedMode] = Seed.modes()
    var activeModeID: String?
    var rig = Rig()
    var simulate: Bool = false
    var shots: [String: ShotNote] = [:]
    var protectedStamps: [String] = []
    var idleMinutes: Int = 5
    /// False until someone picks a sleep time, so older saves of “Awake” pick up the 5 minute idle.
    var idleChosen: Bool = false
    /// Nil until the Apple panel is touched, which means every Core Image effect is offered.
    var appleOn: [String]? = nil
}

enum Disk {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("FXPAN", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var captures: URL {
        let dir = support.appendingPathComponent("Captures", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func load() -> Persisted {
        let url = support.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: url),
              var state = try? JSONDecoder().decode(Persisted.self, from: data) else {
            var fresh = Persisted()
            #if targetEnvironment(simulator)
            fresh.simulate = true
            #endif
            return fresh
        }
        if state.modes.isEmpty { state.modes = Seed.modes() }
        return state
    }

    static func save(_ state: Persisted) {
        let url = support.appendingPathComponent("state.json")
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func loadPair() -> (t: String, r: String) {
        let url = support.appendingPathComponent("cameras.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return ("", "")
        }
        return (obj["T"] ?? "", obj["R"] ?? "")
    }

    static func savePair(t: String, r: String) {
        let url = support.appendingPathComponent("cameras.json")
        let obj = ["T": t, "R": r]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func freeBytes() -> Int64? {
        let vals = try? captures.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return vals?.volumeAvailableCapacityForImportantUsage
    }

    static func fmtBytes(_ n: Int64) -> String {
        if n >= 1_000_000_000_000 { return String(format: "%.1f TB", Double(n) / 1e12) }
        if n >= 1_000_000_000 { return String(format: "%.1f GB", Double(n) / 1e9) }
        return "\(n / 1_000_000) MB"
    }
}

struct ShotFiles: Identifiable, Equatable {
    var stamp: String
    var t: URL?
    var r: URL?
    var nefT: URL?
    var nefR: URL?
    var pano: URL?
    var ana: URL?
    var id: String { stamp }
    var ready: Bool { t != nil && r != nil }

    /// `20261002114100` — year, month, day, then hour minute second.
    var name: String {
        let digits = stamp.filter(\.isNumber)
        if digits.count >= 14 { return String(digits.prefix(14)) }
        return stamp
    }
}

#if targetEnvironment(simulator)
/// Display copies of real stitches, so Playback has pictures when Xcode runs the simulator.
enum SampleShots {
    private static let files = [
        "P_20261002201628.jpg", "P_20261002201628.json",
        "P_20261002195445.jpg", "P_20261002195445.json",
        "P_20261002201952.jpg", "P_20261002201952.json",
    ]

    static func install() {
        let mark = Disk.support.appendingPathComponent("sample-panos")
        if FileManager.default.fileExists(atPath: mark.path) { return }
        var placed = 0
        for name in files {
            let stem = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            guard let src = Bundle.main.url(forResource: stem, withExtension: ext, subdirectory: "Samples")
                    ?? Bundle.main.url(forResource: stem, withExtension: ext) else { continue }
            let dest = Disk.captures.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: dest.path) {
                placed += 1
                continue
            }
            if (try? FileManager.default.copyItem(at: src, to: dest)) != nil {
                placed += 1
            }
        }
        if placed > 0 {
            try? Data("1".utf8).write(to: mark)
        }
    }
}
#endif

enum CaptureIndex {
    static func stampNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: Date())
    }

    /// A test capture named `probe` is not a date. Give it the day and time the file was written.
    static func renameLegacy(stamp from: String) -> String? {
        let root = Disk.captures
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let hits = names.filter { name in
            let stem = (name as NSString).deletingPathExtension
            return stem == "T_\(from)" || stem == "R_\(from)" || stem == "P_\(from)" || stem == "P_\(from)_ana"
        }
        guard !hits.isEmpty else { return nil }
        let dated = hits.compactMap { name -> Date? in
            let url = root.appendingPathComponent(name)
            return (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        }
        let when = dated.max() ?? Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMddHHmmss"
        let stamp = f.string(from: when)
        for name in hits {
            let ext = (name as NSString).pathExtension
            let stem = (name as NSString).deletingPathExtension
            let role = stem.hasPrefix("P_") ? "P" : String(stem.prefix(1))
            let suffix = stem.hasSuffix("_ana") ? "_ana" : ""
            let dest = root.appendingPathComponent("\(role)_\(stamp)\(suffix).\(ext)")
            if FileManager.default.fileExists(atPath: dest.path) { continue }
            try? FileManager.default.moveItem(at: root.appendingPathComponent(name), to: dest)
        }
        let json = root.appendingPathComponent("P_\(from).json")
        let jsonDest = root.appendingPathComponent("P_\(stamp).json")
        if FileManager.default.fileExists(atPath: json.path), !FileManager.default.fileExists(atPath: jsonDest.path) {
            try? FileManager.default.moveItem(at: json, to: jsonDest)
        }
        return stamp
    }

    static func list() -> [ShotFiles] {
        let root = Disk.captures
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        var by: [String: ShotFiles] = [:]
        for name in names {
            let url = root.appendingPathComponent(name)
            if let shot = parse(name: name, url: url) {
                var row = by[shot.stamp] ?? ShotFiles(stamp: shot.stamp)
                if shot.t != nil { row.t = shot.t }
                if shot.r != nil { row.r = shot.r }
                if shot.nefT != nil { row.nefT = shot.nefT }
                if shot.nefR != nil { row.nefR = shot.nefR }
                if shot.pano != nil { row.pano = shot.pano }
                if shot.ana != nil { row.ana = shot.ana }
                by[shot.stamp] = row
            }
        }
        return by.values.sorted { $0.name > $1.name }
    }

    private static func parse(name: String, url: URL) -> ShotFiles? {
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.lowercased()
        if stem.hasPrefix("P_"), stem.hasSuffix("_ana"), ext == "jpg" || ext == "jpeg" {
            let stamp = String(stem.dropFirst(2).dropLast(4))
            return ShotFiles(stamp: stamp, ana: url)
        }
        if stem.hasPrefix("P_"), ext == "jpg" || ext == "jpeg" {
            return ShotFiles(stamp: String(stem.dropFirst(2)), pano: url)
        }
        guard stem.count > 2, stem.dropFirst(1).hasPrefix("_") else { return nil }
        let role = stem.prefix(1)
        let stamp = String(stem.dropFirst(2))
        guard role == "T" || role == "R" else { return nil }
        var row = ShotFiles(stamp: stamp)
        if ext == "nef" {
            if role == "T" { row.nefT = url } else { row.nefR = url }
        } else if ext == "jpg" || ext == "jpeg" {
            if role == "T" { row.t = url } else { row.r = url }
        } else {
            return nil
        }
        return row
    }

    static func delete(stamp: String) {
        let root = Disk.captures
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let stems: Set<String> = ["T_\(stamp)", "R_\(stamp)", "P_\(stamp)", "P_\(stamp)_ana"]
        for name in names {
            let stem = (name as NSString).deletingPathExtension
            guard stems.contains(stem) else { continue }
            try? FileManager.default.removeItem(at: root.appendingPathComponent(name))
        }
        LookStore.remove(stamp)
    }
}

/// The unstyled stitch, kept so a saved look can be replaced without grading a graded file.
enum LookStore {
    static func plain(stamp: String, ana: Bool) -> URL? {
        let url = directory().appendingPathComponent(ana ? "P_\(stamp)_ana.jpg" : "P_\(stamp).jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func remove(_ stamp: String) {
        try? FileManager.default.removeItem(at: directory().appendingPathComponent("P_\(stamp).jpg"))
        try? FileManager.default.removeItem(at: directory().appendingPathComponent("P_\(stamp)_ana.jpg"))
    }

    static func keep(stamp: String, look: LookSet, pano: URL, ana: URL) throws {
        let dir = directory()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let panoBase = dir.appendingPathComponent("P_\(stamp).jpg")
        let anaBase = dir.appendingPathComponent("P_\(stamp)_ana.jpg")
        if !FileManager.default.fileExists(atPath: panoBase.path) {
            try FileManager.default.copyItem(at: pano, to: panoBase)
        }
        if FileManager.default.fileExists(atPath: ana.path), !FileManager.default.fileExists(atPath: anaBase.path) {
            try FileManager.default.copyItem(at: ana, to: anaBase)
        }
        try write(from: panoBase, to: pano, look: look)
        if FileManager.default.fileExists(atPath: anaBase.path) {
            try write(from: anaBase, to: ana, look: look)
        }
    }

    private static func directory() -> URL {
        Disk.captures.appendingPathComponent("look", isDirectory: true)
    }

    private static func write(from source: URL, to dest: URL, look: LookSet) throws {
        if LookBook.identity(look) {
            guard source.path != dest.path else { return }
            let tmp = dest.appendingPathExtension("writing")
            try? FileManager.default.removeItem(at: tmp)
            try FileManager.default.copyItem(at: source, to: tmp)
            _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
            return
        }
        guard let image = Stitcher.image(at: source) else {
            throw PTPError.message("Could not read the panorama")
        }
        let graded = Stitcher.grade(image, look: look)
        let tmp = dest.appendingPathExtension("writing")
        try? FileManager.default.removeItem(at: tmp)
        try Stitcher.jpeg(graded, to: tmp)
        _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)
    }
}
