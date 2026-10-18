import SwiftUI

struct MeterRead: Equatable {
    var online = false
    var mirrorUp = false
    var counts: Int?
    /// Why counts is empty: the property list, and the get's reply.
    var detail = ""
}

struct MeterPlan: Equatable {
    var lines: [String]
    var shutter: String?
    var iso: String?
    /// True when the proposal differs from the dials and can be written.
    var ready: Bool
}

/// The shutter speed where ISO starts to carry the exposure, and the highest ISO before the shutter is allowed to go slower.
struct MeterAim: Equatable {
    var maxISO: Double
    var slowest: Double
}

/// Turns the master's prism bar into a shutter and an ISO.
enum ExposureMeter {
    /// One count on 0xD1B1.
    static let count = 1.0 / 12.0
    /// Leave the dials alone inside two counts of the body's zero.
    private static let hold = 2.0 / 12.0
    /// The prism is already calibrated. Zero is the exposure.
    static let targetCounts = 0

    static func stops(counts: Int) -> Double { Double(counts) * count }

    static func aim(of light: LightSet) -> MeterAim {
        let iso = Double(light.maxISO.filter(\.isNumber)) ?? 3200
        let slow = seconds(light.slowest) ?? (1.0 / 60)
        return MeterAim(maxISO: max(100, iso), slowest: max(1.0 / 8000, slow))
    }

    static let programHint = "The shutter is solved first, down to the minimum speed, at ISO 100. ISO climbs the whole list only when the shutter would be slower, and a bright bar walks it back down before the shutter speeds up."

    static func plan(master: Role, read: MeterRead?, shutter: String, iso: String, kind: BodyKind, aim: MeterAim? = nil) -> MeterPlan {
        let who = master.rawValue
        guard let read, read.online else {
            return MeterPlan(lines: ["\(who) is off USB"], shutter: nil, iso: nil, ready: false)
        }
        guard let counts = read.counts else {
            let why = read.detail.isEmpty ? "meter did not answer" : read.detail
            return MeterPlan(lines: ["\(who) \(why)"], shutter: nil, iso: nil, ready: false)
        }
        let measured = stops(counts: counts)
        var lines = ["Master \(who) · \(fmt(measured))"]
        if abs(counts) >= 60 {
            lines.append("The bar is at its end, so the miss may be larger")
        }
        if read.mirrorUp {
            lines.append("The mirror is up, so this is the last prism reading")
        }
        guard let current = seconds(shutter), let isoNow = Double(iso.filter(\.isNumber)), isoNow > 0 else {
            lines.append("Set a shutter and an ISO, then the bar can move them")
            return MeterPlan(lines: lines, shutter: nil, iso: nil, ready: false)
        }
        let error = measured
        // Inside the hold the exposure stays put, but the pair still sits on the program line: lowest ISO that keeps the shutter at the minimum.
        let need = aim == nil && abs(error) < hold ? nil : (abs(error) < hold ? 0 : -error)
        if need == nil {
            lines.append("\(Catalog.fmtShut(shutter)) · \(Catalog.fmtISO(iso, kind: kind)) holds")
            return MeterPlan(lines: lines, shutter: shutter, iso: iso, ready: false)
        }
        let next = aim.map { program(seconds: current, iso: isoNow, need: need ?? 0, aim: $0) }
            ?? balance(seconds: current, iso: isoNow, need: need ?? 0)
        let changed = next.shutter != shutter || next.iso != iso
        if !changed {
            lines.append("\(Catalog.fmtShut(shutter)) · \(Catalog.fmtISO(iso, kind: kind)) holds")
            return MeterPlan(lines: lines, shutter: shutter, iso: iso, ready: false)
        }
        if abs(error) < hold {
            lines.append("On zero, so the pair sits on the minimum shutter")
        } else {
            let way = error < 0 ? "dark of zero" : "bright of zero"
            lines.append("\(String(format: "%.1f", abs(error))) \(way)")
        }
        lines.append("\(Catalog.fmtShut(shutter)) → \(Catalog.fmtShut(next.shutter))")
        lines.append("\(Catalog.fmtISO(iso, kind: kind)) → \(Catalog.fmtISO(next.iso, kind: kind))")
        return MeterPlan(lines: lines, shutter: next.shutter, iso: next.iso, ready: true)
    }

    /// Half the bar moves the shutter, half moves ISO. Either can run to the end of its list, from 30 seconds to 1/8000 and from ISO 100 to 25600. What one cannot take, the other does.
    private static func balance(seconds current: Double, iso isoNow: Double, need: Double) -> (shutter: String, iso: String) {
        let fastest = 1.0 / 8000
        let slowest = 30.0
        var sec = min(max(current * pow(2, need / 2), fastest), slowest)
        var left = need - log2(sec / current)
        var iso = min(max(isoNow * pow(2, left), 100), 25600)
        left -= log2(iso / isoNow)
        if abs(left) >= 0.08 {
            sec = min(max(sec * pow(2, left), fastest), slowest)
        }
        return (nearestShutter(sec), nearestISO(iso))
    }

    /// A repeated peg is one more stop, not another full five. The bar cannot show anything past its end.
    static func settled(counts: Int, held: Int?) -> Int {
        guard counts == held else { return counts }
        guard abs(counts) >= 60 else { return targetCounts }
        return targetCounts + (counts > 0 ? 12 : -12)
    }

    /// Aperture-priority auto ISO, the order Nikon, Fuji, and Sony publish.
    /// Solve the shutter at ISO 100. Climb the list only when that shutter would be slower than the minimum, and walk back down it before the shutter goes faster. Past the maximum ISO, the shutter may be slower than the minimum.
    private static func program(seconds current: Double, iso isoNow: Double, need: Double, aim: MeterAim) -> (shutter: String, iso: String) {
        let fastest = 1.0 / 8000.0
        let slowest = 30.0
        let base = 100.0
        let ceiling = 25600.0
        let floor = min(max(aim.slowest, fastest), slowest)
        let maxISO = min(max(aim.maxISO, base), ceiling)
        let sec = min(max(current, fastest), slowest)
        let iso = min(max(isoNow, base), ceiling)
        let product = sec * iso * pow(2.0, need)
        var nextISO = min(max(product / floor, base), maxISO)
        var nextSec = product / nextISO
        if nextSec < fastest {
            nextSec = fastest
            nextISO = min(max(product / nextSec, base), maxISO)
        } else if nextSec > slowest {
            nextSec = slowest
            nextISO = min(max(product / nextSec, base), maxISO)
        }
        // Snap to a listed ISO, then give the shutter what remains. A third-stop miss stays a third stop instead of rounding up into Hi.
        if let snapped = Double(nearestISO(nextISO, cap: maxISO)), snapped > 0 {
            nextISO = snapped
            nextSec = product / nextISO
            if nextSec < fastest {
                nextSec = fastest
                nextISO = min(max(product / nextSec, base), maxISO)
            } else if nextSec > slowest {
                nextSec = slowest
                nextISO = min(max(product / nextSec, base), maxISO)
            }
        }
        return (nearestShutter(nextSec), nearestISO(nextISO, cap: maxISO))
    }

    static func fmt(_ stops: Double) -> String {
        String(format: "%+.1f", stops)
    }

    private static func seconds(_ v: String) -> Double? {
        if Catalog.isAuto(v) { return nil }
        let slash = v.split(separator: "/").map(String.init)
        if slash.count == 2, let n = Double(slash[0]), let d = Double(slash[1]), d != 0 {
            return n / d
        }
        return Double(v)
    }

    private static func nearestShutter(_ seconds: Double, noSlowerThan floor: Double? = nil) -> String {
        let choices = Catalog.shutter.filter { value in
            guard !Catalog.isAuto(value), let sec = self.seconds(value) else { return false }
            if let floor, sec > floor * 1.02 { return false }
            return true
        }
        return choices.min { a, b in
            abs(log2((self.seconds(a) ?? seconds) / seconds)) < abs(log2((self.seconds(b) ?? seconds) / seconds))
        } ?? "1/250"
    }

    private static func nearestISO(_ value: Double, cap: Double? = nil) -> String {
        let choices = Catalog.iso.filter { raw in
            guard !Catalog.isAuto(raw), let n = Double(raw) else { return false }
            if let cap, n > cap * 1.01 { return false }
            return true
        }
        return choices.min { a, b in
            let da = log2((Double(a) ?? value) / value)
            let db = log2((Double(b) ?? value) / value)
            return abs(da) < abs(db)
        } ?? "400"
    }
}

struct MeterScreen: View {
    @Environment(AppModel.self) private var model
    @State private var reads: [Role: MeterRead] = [:]
    /// The bar we already turned into a shutter and ISO. The same count must not be applied twice.
    @State private var followedCounts: Int?
    @State private var followedAt = Date.distantPast

    var body: some View {
        let master = Role(rawValue: model.photo.light.master) ?? .t
        let auto = model.photo.light.autoMeter
        let live = auto ? model.meterReads : reads
        let aim = auto ? ExposureMeter.aim(of: model.photo.light) : nil
        let plan = ExposureMeter.plan(
            master: master,
            read: reading(for: master, live: live),
            shutter: model.photo.light.shutter,
            iso: model.photo.light.iso,
            kind: model.bodyKind,
            aim: aim
        )
        DimPage(title: "Meter", crumb: "Light", controls: {
            VStack(alignment: .leading, spacing: 10) {
                RowBlock(title: "From the master", value: master.rawValue, hint: auto ? "Auto is writing these limits to both bodies." : "The bar settles on the body's zero. Half the miss moves the shutter, half moves ISO.") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.lines, id: \.self) { line in
                            Text(line)
                                .font(Theme.font(15))
                                .foregroundStyle(Theme.ink)
                        }
                    }
                }
                Button {
                    guard let shutter = plan.shutter, let iso = plan.iso else { return }
                    model.edit {
                        $0.light.program = "M"
                        $0.light.followCam = false
                        $0.light.shutter = shutter
                        $0.light.iso = iso
                    }
                } label: {
                    Text("Use these")
                        .font(Theme.font(16, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(plan.ready && !model.shooting && !auto ? Theme.goldInk : Theme.dim)
                        .background(plan.ready && !model.shooting && !auto ? Theme.gold : Theme.s2, in: RoundedRectangle(cornerRadius: Theme.radius))
                }
                .disabled(!plan.ready || model.shooting || auto)
                Text(auto ? "Auto is on, so the dials follow the bar." : "Use these writes manual shutter and ISO to both bodies.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.faint)
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 10) {
                needle(.t, master: master, live: live)
                needle(.r, master: master, live: live)
                suggestion(plan, auto: auto)
            }
        })
        .onChange(of: reads) { _, _ in
            guard !model.photo.light.autoMeter else { return }
            follow(plan, counts: reads[master]?.counts)
        }
        .task(id: auto) {
            guard !auto else { return }
            while !Task.isCancelled {
                if !model.shooting {
                    reads = await model.camera.readMeters()
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    /// A bar we already turned into shutter and ISO counts as the aim, so the same reading cannot stack another correction.
    private func reading(for master: Role, live: [Role: MeterRead]) -> MeterRead? {
        guard var read = live[master] else { return nil }
        if !model.photo.light.autoMeter, let counts = read.counts {
            read.counts = ExposureMeter.settled(counts: counts, held: followedCounts)
        }
        return read
    }

    /// Write the proposal while this page is open. Wait for a new bar, so a stale count cannot stack another correction.
    private func follow(_ plan: MeterPlan, counts: Int?) {
        guard plan.ready, !model.shooting, let counts, let shutter = plan.shutter, let iso = plan.iso else { return }
        if counts == followedCounts { return }
        if Date().timeIntervalSince(followedAt) < 1.5 { return }
        followedCounts = counts
        followedAt = Date()
        model.edit {
            $0.light.program = "M"
            $0.light.followCam = false
            $0.light.shutter = shutter
            $0.light.iso = iso
        }
    }

    private func suggestion(_ plan: MeterPlan, auto: Bool) -> some View {
        let shutter = plan.shutter.map(Catalog.fmtShut) ?? "—"
        let iso = plan.iso.map { Catalog.fmtISO($0, kind: model.bodyKind) } ?? "—"
        let hint = auto
            ? ExposureMeter.programHint
            : "Half the bar moves the shutter, half moves ISO. Both run to the end of the list."
        return RowBlock(title: "Sets", value: plan.ready ? "Chasing" : "Holding", hint: hint) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(shutter)
                    .font(Theme.font(28, weight: .medium))
                Text(iso)
                    .font(Theme.font(22, weight: .medium))
                    .foregroundStyle(Theme.ink2)
            }
        }
    }

    private func needle(_ role: Role, master: Role, live: [Role: MeterRead]) -> some View {
        let read = live[role]
        let tint = role == .t ? Theme.transmit : Theme.reflect
        let stops = read?.counts.map(ExposureMeter.stops(counts:))
        let value: String = {
            guard let read, read.online else { return "Off USB" }
            guard let stops else { return "No meter" }
            return ExposureMeter.fmt(stops)
        }()
        return RowBlock(title: role == master ? "\(role.rawValue) · master" : role.rawValue, value: value) {
            VStack(alignment: .leading, spacing: 6) {
                NeedleBar(stops: stops, tint: tint)
                HStack {
                    Text("−5")
                    Spacer()
                    Text(read?.mirrorUp == true ? "Mirror up" : "0")
                    Spacer()
                    Text("+5")
                }
                .font(Theme.font(11))
                .foregroundStyle(Theme.faint)
            }
        }
    }
}

/// The prism bar, minus on the left. The mark sits on zero when the reading is missing.
private struct NeedleBar: View {
    var stops: Double?
    var tint: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let mid = w / 2
            let span = 5.0
            let mark = stops.map { mid + CGFloat($0 / span) * (w / 2) } ?? mid
            let x = min(max(mark, 8), w - 8)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.s3)
                Rectangle()
                    .fill(Theme.hair2)
                    .frame(width: 1, height: h)
                    .position(x: mid, y: h / 2)
                Circle()
                    .fill(stops == nil ? Theme.faint : tint)
                    .frame(width: 14, height: 14)
                    .position(x: x, y: h / 2)
            }
        }
        .frame(height: 22)
    }
}
