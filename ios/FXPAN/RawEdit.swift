import SwiftUI

/// A develop of one NEF. Exposure and white balance are still linear scene light.
/// Tone, detail, and noise are what CIRAW applies after that, which is the order in RawTherapee and in darktable's pixelpipe.
struct RawGrade: Codable, Equatable, Hashable {
    var exposure: Float = 0
    var temperature: Float = 5500
    var tint: Float = 0
    var asShotWB: Bool = true
    var pickX: Float?
    var pickY: Float?
    var boost: Float = 1
    var shadow: Float = 1
    var shadowBias: Float = 0
    var localTone: Float = 0
    var contrast: Float = 0
    var detail: Float = 0
    var sharp: Float = 0
    var luma: Float = 0
    var chroma: Float = 0
    var moire: Float = 0
    var lens: Bool = false
    var highlights: Bool = true
    var gamut: Bool = true
    var edr: Float = 0
}

struct RawFrame: @unchecked Sendable {
    var image: CGImage
    var bins: [Int]
}

enum RawBook {
    private struct Pair: Codable {
        var t: RawGrade?
        var r: RawGrade?
    }

    static func load(stamp: String) -> [String: RawGrade] {
        guard let data = try? Data(contentsOf: file(stamp)),
              let pair = try? JSONDecoder().decode(Pair.self, from: data) else { return [:] }
        var grades: [String: RawGrade] = [:]
        if let t = pair.t { grades["T"] = t }
        if let r = pair.r { grades["R"] = r }
        return grades
    }

    static func save(stamp: String, grades: [String: RawGrade]) {
        let pair = Pair(t: grades["T"], r: grades["R"])
        guard let data = try? JSONEncoder().encode(pair) else { return }
        try? data.write(to: file(stamp), options: .atomic)
    }

    /// A grade saved from the raw screen for this NEF. Missing means the stitch keeps its usual CIRAW path.
    static func grade(for url: URL) -> RawGrade? {
        let stem = url.deletingPathExtension().lastPathComponent
        let parts = stem.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return load(stamp: String(parts[1]))[String(parts[0])]
    }

    private static func file(_ stamp: String) -> URL {
        Disk.captures.appendingPathComponent("E_\(stamp).json")
    }
}

struct RawScreen: View {
    @Environment(AppModel.self) private var model
    var stamp: String
    @State private var role = "T"
    @State private var saved: [String: RawGrade] = [:]
    @State private var baseline: [String: RawGrade] = [:]
    @State private var ability: [String: RawAbility] = [:]
    @State private var image: UIImage?
    @State private var generation = 0
    @State private var bins: [Int] = []
    @State private var before = false
    @State private var picking = false
    @State private var clip = false
    @State private var writing = false
    @State private var status = ""

    private var shot: ShotFiles? { model.shots.first { $0.stamp == stamp } }

    private var url: URL? { role == "R" ? shot?.nefR : shot?.nefT }

    private var shown: RawGrade { saved[role] ?? baseline[role] ?? RawGrade() }

    private var ready: Bool { saved[role] != nil || baseline[role] != nil }

    private var can: RawAbility { ability[role] ?? RawAbility() }

    private var roles: [(String, String)] {
        var rows: [(String, String)] = []
        if shot?.nefT != nil { rows.append(("T", "T")) }
        if shot?.nefR != nil { rows.append(("R", "R")) }
        return rows
    }

    var body: some View {
        DimPage(title: shot?.name ?? "Raw", crumb: "Playback", stickPanel: true, controls: {
            controls
        }, panel: {
            picture
        })
        .task(id: stamp) { await open() }
        .onChange(of: previewToken, initial: true) { _, _ in schedule() }
    }

    private var previewToken: String {
        "\(role)|\(url?.path ?? "")|\(before)|\(clip)|\(model.highISO)|\(model.plateOn)|\(shown.exposure)|\(shown.hashValue)"
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            if roles.isEmpty {
                Text("This set has no NEF. The camera JPEG is already baked.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.dim)
            } else if !ready {
                Text("Opening the NEF")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.dim)
            } else {
                ChipRow(options: roles, selected: role) { role = $0; schedule() }
                histogram
                exposure
                balance
                tone
                highISO
                plate
                detail
                lens
                actions
                if !status.isEmpty {
                    Text(status).font(Theme.font(12)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var histogram: some View {
        Canvas { context, size in
            let peak = CGFloat(bins.max() ?? 1)
            guard peak > 0, !bins.isEmpty else { return }
            var path = Path()
            let step = size.width / CGFloat(bins.count)
            path.move(to: CGPoint(x: 0, y: size.height))
            for (index, count) in bins.enumerated() {
                let x = CGFloat(index) * step
                let y = size.height - (CGFloat(count) / peak) * size.height
                path.addLine(to: CGPoint(x: x, y: y))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
            context.fill(path, with: .color(Theme.gold.opacity(0.85)))
        }
        .frame(height: 56)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radiusS))
    }

    private var exposure: some View {
        RowBlock(title: "Exposure", value: String(format: "%+.1f", shown.exposure), hint: "Stops of linear light, before the tone curve.") {
            slider(shown.exposure, -3...3) { grade, value in
                grade.exposure = value
            }
        }
    }

    private var balance: some View {
        RowBlock(title: "White balance", value: shown.asShotWB && shown.pickX == nil ? "As shot" : "\(Int(shown.temperature)) K", hint: "Scene white, while the data is still linear. Pick samples a point in the frame.") {
            VStack(alignment: .leading, spacing: 8) {
                slider(shown.temperature, 2500...10000) { grade, value in
                    grade.temperature = value
                    grade.asShotWB = false
                    grade.pickX = nil
                    grade.pickY = nil
                }
                HStack {
                    Text("Tint").font(Theme.font(13))
                    Spacer()
                    Text(String(format: "%+.0f", shown.tint)).font(Theme.font(13)).foregroundStyle(Theme.dim)
                }
                slider(shown.tint, -150...150) { grade, value in
                    grade.tint = value
                    grade.asShotWB = false
                    grade.pickX = nil
                    grade.pickY = nil
                }
                HStack(spacing: 8) {
                    PressChip(title: picking ? "Tap the frame" : "Pick", on: picking) { picking.toggle() }
                    PressChip(title: "As shot", on: shown.asShotWB && shown.pickX == nil) { asShot() }
                }
            }
        }
    }

    private var tone: some View {
        RowBlock(title: "Tone", value: String(format: "%.2f", shown.boost), hint: "The curve that fits the frame on the screen. Local tone gives each area its own.") {
            VStack(alignment: .leading, spacing: 8) {
                labeled("Curve", shown.boost)
                slider(shown.boost, 0...1) { $0.boost = $1 }
                labeled("Shadows", shown.shadow)
                slider(shown.shadow, 0...2) { $0.shadow = $1 }
                labeled("Shadow bias", shown.shadowBias)
                slider(shown.shadowBias, -2...4) { $0.shadowBias = $1 }
                if can.local {
                    labeled("Local", shown.localTone)
                    slider(shown.localTone, 0...1) { $0.localTone = $1 }
                } else {
                    Text("No local tone map in this NEF")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                }
                labeled("Contrast", shown.contrast)
                slider(shown.contrast, 0...1) { $0.contrast = $1 }
            }
        }
    }

    private var highISO: some View {
        Toggle(isOn: Binding(get: { model.highISO }, set: { model.setHighISO($0); schedule() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("High ISO reduction").font(Theme.font(16, weight: .medium))
                Text(NoiseBook.caption(url: url))
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
            }
        }
        .tint(Theme.gold)
        .padding(12)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var plate: some View {
        Toggle(isOn: Binding(get: { model.plateOn }, set: { model.setPlate($0); schedule() })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Plate correction").font(Theme.font(16, weight: .medium))
                Text("Color match, fringe, and flat from the printed sheet.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
            }
        }
        .tint(Theme.gold)
        .padding(12)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var detail: some View {
        RowBlock(title: "Detail", value: String(format: "%.2f", shown.sharp), hint: "Edges and noise, after the color is set.") {
            VStack(alignment: .leading, spacing: 8) {
                labeled("Sharp", shown.sharp)
                slider(shown.sharp, 0...1) { $0.sharp = $1 }
                labeled("Detail", shown.detail)
                slider(shown.detail, 0...1) { $0.detail = $1 }
                labeled("Luma noise", shown.luma)
                slider(shown.luma, 0...1) { $0.luma = $1 }
                labeled("Color noise", shown.chroma)
                slider(shown.chroma, 0...1) { $0.chroma = $1 }
                labeled("Moire", shown.moire)
                slider(shown.moire, 0...1) { $0.moire = $1 }
            }
        }
    }

    private var lens: some View {
        RowBlock(title: "Lens", value: shown.lens ? "On" : "Off", hint: "The CPU profile in the NEF, plus highlight recovery and gamut.") {
            VStack(alignment: .leading, spacing: 8) {
                if can.lens {
                    ChipRow(options: [("1", "Correction"), ("0", "Off")], selected: shown.lens ? "1" : "0") { value in
                        edit { $0.lens = value == "1" }
                    }
                } else {
                    Text("No lens profile in this NEF")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                }
                if can.highlights {
                    ChipRow(options: [("1", "Highlights"), ("0", "Clip")], selected: shown.highlights ? "1" : "0") { value in
                        edit { $0.highlights = value == "1" }
                    }
                }
                ChipRow(options: [("1", "Gamut"), ("0", "Off")], selected: shown.gamut ? "1" : "0") { value in
                    edit { $0.gamut = value == "1" }
                }
                labeled("Extended range", shown.edr)
                slider(shown.edr, 0...2) { $0.edr = $1 }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                PressChip(title: "Clip", on: clip) { clip.toggle(); schedule() }
                Text("Hold original")
                    .font(Theme.font(15, weight: before ? .semibold : .medium))
                    .foregroundStyle(before ? Theme.gold : Theme.ink)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.s2, in: Capsule())
                    .overlay(Capsule().stroke(before ? Theme.gold : Theme.hair2, lineWidth: 1))
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                if !before { before = true; schedule() }
                            }
                            .onEnded { _ in before = false; schedule() }
                    )
            }
            HStack(spacing: 8) {
                Button("Reset") { reset() }
                    .buttonStyle(PlainChip())
                Button("Match other") { match() }
                    .buttonStyle(PlainChip())
                    .disabled(roles.count < 2)
            }
            Button(writing ? "Writing" : "Write JPEG") { Task { await write() } }
                .buttonStyle(GoldButton())
                .disabled(writing || url == nil)
            Button(model.shooting ? (model.stitchLabel ?? "Stitching") : "Stitch with this") {
                model.edit { $0.drive.ciraw = true }
                model.restitch(stamp)
                status = "Stitching with this grade"
            }
            .buttonStyle(GoldButton())
            .disabled(model.shooting || roles.count < 2)
            Text("Write keeps a JPEG of this body. Stitch develops both NEFs with the grades saved here.")
                .font(Theme.font(12))
                .foregroundStyle(Theme.dim)
        }
    }

    private var picture: some View {
        GeometryReader { geo in
            let size = image?.size ?? CGSize(width: 3, height: 1)
            let fit = Self.fitted(size, in: geo.size)
            ZStack {
                Color.black
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .id(generation)
                    if let x = shown.pickX, let y = shown.pickY, !before {
                        Circle()
                            .stroke(Theme.gold, lineWidth: 1.5)
                            .background(Circle().fill(Theme.gold.opacity(0.35)))
                            .frame(width: 14, height: 14)
                            .position(x: fit.minX + CGFloat(x) * fit.width, y: fit.minY + CGFloat(1 - y) * fit.height)
                    }
                } else {
                    Text(url == nil ? "No NEF" : "Developing")
                        .font(Theme.font(16, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onEnded { value in
                    guard picking else { return }
                    let x = (value.location.x - fit.minX) / max(fit.width, 1)
                    let y = (value.location.y - fit.minY) / max(fit.height, 1)
                    guard (0...1).contains(x), (0...1).contains(y) else { return }
                    edit {
                        $0.pickX = Float(x)
                        $0.pickY = Float(1 - y)
                        $0.asShotWB = false
                    }
                    picking = false
                }
            )
        }
    }

    private func labeled(_ title: String, _ value: Float) -> some View {
        HStack {
            Text(title).font(Theme.font(13))
            Spacer()
            Text(String(format: "%+.2f", value)).font(Theme.font(13)).foregroundStyle(Theme.dim)
        }
    }

    private func slider(_ value: Float, _ range: ClosedRange<Float>, _ apply: @escaping (inout RawGrade, Float) -> Void) -> some View {
        Slider(
            value: Binding(
                get: { Double(min(range.upperBound, max(range.lowerBound, value))) },
                set: { new in edit { apply(&$0, Float(new)) } }
            ),
            in: Double(range.lowerBound)...Double(range.upperBound)
        )
        .tint(Theme.gold)
    }

    private func edit(_ body: (inout RawGrade) -> Void) {
        var grade = shown
        body(&grade)
        saved[role] = grade
        RawBook.save(stamp: stamp, grades: saved)
        schedule()
    }

    private func asShot() {
        edit {
            if let base = baseline[role] {
                $0.temperature = base.temperature
                $0.tint = base.tint
            }
            $0.asShotWB = true
            $0.pickX = nil
            $0.pickY = nil
        }
    }

    private func reset() {
        saved[role] = nil
        RawBook.save(stamp: stamp, grades: saved)
        status = ""
        schedule()
    }

    private func match() {
        let other = role == "T" ? "R" : "T"
        guard roles.contains(where: { $0.0 == other }) else { return }
        saved[other] = shown
        RawBook.save(stamp: stamp, grades: saved)
        status = "Matched \(other)"
    }

    private func open() async {
        let files: [(String, URL?)] = [("T", shot?.nefT), ("R", shot?.nefR)]
        let loaded = RawBook.load(stamp: stamp)
        var base: [String: RawGrade] = [:]
        for item in files {
            guard let file = item.1 else { continue }
            if let grade = await Task.detached(priority: .userInitiated, operation: { RawDevelop.baseline(at: file) }).value {
                base[item.0] = grade
            }
        }
        saved = loaded
        baseline = base
        var can: [String: RawAbility] = [:]
        for item in files {
            if let file = item.1 { can[item.0] = RawDevelop.ability(for: file) }
        }
        ability = can
        if url == nil, shot?.nefR != nil { role = "R" }
        schedule()
    }

    private func schedule() {
        guard let url else {
            image = nil
            return
        }
        let grade = before ? (baseline[role] ?? shown) : shown
        let mark = clip && !before
        Task {
            guard let frame = await RawDevelop.enqueuePreview(url: url, grade: grade, clip: mark) else { return }
            image = UIImage(cgImage: frame.image)
            bins = frame.bins
            generation += 1
        }
    }

    private func write() async {
        guard let url else { return }
        writing = true
        let grade = shown
        let role = role
        let stamp = stamp
        let wrote = await Task.detached(priority: .userInitiated, operation: { () -> Bool in
            guard let image = RawDevelop.image(at: url, lens: grade.lens, apple: false, grade: grade) else { return false }
            let dest = Disk.captures.appendingPathComponent("\(role)_\(stamp)_dev.jpg")
            do {
                try Stitcher.jpeg(image, to: dest)
                return true
            } catch {
                return false
            }
        }).value
        writing = false
        status = wrote ? "Wrote \(role) JPEG" : "Could not write \(role)"
    }

    private static func fitted(_ image: CGSize, in box: CGSize) -> CGRect {
        guard image.width > 0, image.height > 0, box.width > 0, box.height > 0 else {
            return CGRect(origin: .zero, size: box)
        }
        let scale = min(box.width / image.width, box.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2, width: size.width, height: size.height)
    }
}
