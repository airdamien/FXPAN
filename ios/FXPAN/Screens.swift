import ImageIO
import SwiftUI

struct FrameScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "Frame", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Format", value: Catalog.format(model.photo.frame.squeeze).1) {
                    ChipRow(options: Catalog.formats.map { (String($0.0), $0.1) }, selected: String(Catalog.format(model.photo.frame.squeeze).0)) { value in
                        model.edit { $0.frame.squeeze = Double(value) ?? 1 }
                    }
                }
                RowBlock(title: "Guide", value: Catalog.guide(model.photo.frame.guide).2, hint: "Frame lines to compose inside") {
                    ChipRow(options: Catalog.guides.map { ($0.0, $0.2) }, selected: model.photo.frame.guide) { value in
                        model.edit { $0.frame.guide = value }
                    }
                }
                RowBlock(title: "Edges", value: model.photo.frame.clip ? "Clip to aligned" : "Full canvas", hint: "After alignment") {
                    ChipRow(options: [("1", "Clip to aligned"), ("0", "Full canvas")], selected: model.photo.frame.clip ? "1" : "0") { value in
                        model.edit { $0.frame.clip = value == "1" }
                    }
                }
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 12) {
                PanoFrame().frame(maxHeight: 280)
                Text("Two frames, \(Int((model.rig.overlap * 100).rounded()))% overlap, one 65:24 strip")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
                HStack(spacing: 8) {
                    Text("R").foregroundStyle(Theme.reflect)
                    RoundedRectangle(cornerRadius: 3).stroke(Theme.reflect, lineWidth: 1).frame(width: 70, height: 46)
                    Text("T").foregroundStyle(Theme.transmit)
                    RoundedRectangle(cornerRadius: 3).stroke(Theme.transmit, lineWidth: 1).frame(width: 70, height: 46)
                    Image(systemName: "arrow.right")
                    Text("2.71:1").foregroundStyle(Theme.gold)
                }
                .font(Theme.font(13, weight: .medium))
            }
        })
    }
}

struct LightScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let _ = model.cameraRevision
        let light = model.photo.light
        DimPage(title: "Light", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Mode", value: light.program) {
                    ChipRow(options: Catalog.programs.map { ($0.0, $0.0) }, selected: light.program) { value in
                        model.edit { $0.light.program = value }
                    }
                }
                RowBlock(title: "ISO", value: Catalog.fmtISO(light.iso), hint: light.followCam ? "Camera decides" : "Both bodies") {
                    Ruler(values: Catalog.iso, selected: light.iso, label: { Catalog.isAuto($0) ? "Auto" : $0 }) { value in
                        model.edit { $0.light.iso = value }
                    }
                }
                RowBlock(title: "Shutter", value: Catalog.fmtShut(light.shutter)) {
                    Ruler(values: Catalog.shutter, selected: light.shutter, label: Catalog.fmtShut) { value in
                        model.edit { $0.light.shutter = value }
                    }
                }
                RowBlock(title: "Aperture", value: Catalog.fmtF(light.fstop), hint: "Taking-lens iris") {
                    Ruler(values: Catalog.fstop, selected: light.fstop, label: { Catalog.isAuto($0) ? "Auto" : $0 }) { value in
                        model.edit { $0.light.fstop = value }
                    }
                }
                RowBlock(title: "Master", value: light.master) {
                    ChipRow(options: [("T", "T"), ("R", "R")], selected: light.master) { value in
                        model.edit { $0.light.master = value }
                    }
                }
                RowBlock(title: "Meter", value: light.followCam ? "Camera" : "FXPAN") {
                    ChipRow(options: [("0", "Set from here"), ("1", "Camera decides")], selected: light.followCam ? "1" : "0") { value in
                        model.edit { $0.light.followCam = value == "1" }
                    }
                }
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 10) {
                bodyLine(.t)
                bodyLine(.r)
                Text(model.camera.line).font(Theme.font(13)).foregroundStyle(Theme.dim)
            }
        })
    }

    private func bodyLine(_ role: Role) -> some View {
        let slot = model.camera.slots[role] ?? BodyState()
        let tint = role == .t ? Theme.transmit : Theme.reflect
        let bits = [slot.program, slot.iso, slot.shutter, slot.fstop.isEmpty ? "" : "f/\(slot.fstop)"].filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 2) {
            Text(role.rawValue).font(Theme.font(13, weight: .semibold)).foregroundStyle(tint)
            Text(slot.online ? bits.joined(separator: " · ") : "off USB")
                .font(Theme.font(14))
                .foregroundStyle(Theme.ink2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct FocusScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "Focus", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Aid", value: model.photo.focus.aid) {
                    ChipRow(options: [("off", "Off"), ("peaking", "Peaking"), ("loupe", "Loupe")], selected: model.photo.focus.aid) { value in
                        model.edit { $0.focus.aid = value }
                    }
                }
                RowBlock(title: "Peak color", value: model.photo.focus.color) {
                    ChipRow(options: Catalog.peakColors.map { ($0.0, $0.1) }, selected: model.photo.focus.color) { value in
                        model.edit { $0.focus.color = value }
                    }
                }
                RowBlock(title: "Level", value: model.photo.focus.level) {
                    ChipRow(options: Catalog.peakLevels.map { ($0, $0.prefix(1).uppercased() + $0.dropFirst()) }, selected: model.photo.focus.level) { value in
                        model.edit { $0.focus.level = value }
                    }
                }
            }
        }, panel: { PanoFrame().frame(maxHeight: 320) })
    }
}

struct LookScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let look = model.photo.look
        DimPage(title: "Look", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Base", value: LookBook.name(look)) {
                    ChipRow(options: LookBook.names.map { ($0.0, $0.1) }, selected: look.base) { value in
                        model.edit {
                            $0.look.base = value
                            $0.look.id = value
                        }
                    }
                }
                if !LookBook.isMono(look) {
                    stepper("Color", look.color) { value in model.edit { $0.look.color = value } }
                } else {
                    RowBlock(title: "Filter", value: look.filter) {
                        ChipRow(options: LookBook.filters.map { ($0, $0.prefix(1).uppercased() + $0.dropFirst()) }, selected: look.filter) { value in
                            model.edit { $0.look.filter = value }
                        }
                    }
                }
                stepper("Highlight", look.highlight) { value in model.edit { $0.look.highlight = value } }
                stepper("Shadow", look.shadow) { value in model.edit { $0.look.shadow = value } }
                RowBlock(title: "Grain", value: look.grain) {
                    ChipRow(options: LookBook.grains.map { ($0, $0.prefix(1).uppercased() + $0.dropFirst()) }, selected: look.grain) { value in
                        model.edit { $0.look.grain = value }
                    }
                }
            }
        }, panel: { PanoFrame(showGuide: false).frame(maxHeight: 320) })
    }

    private func stepper(_ title: String, _ value: Int, _ set: @escaping (Int) -> Void) -> some View {
        RowBlock(title: title, value: Catalog.signed(value)) {
            Ruler(values: LookBook.steps.map(String.init), selected: String(value), label: { Catalog.signed(Int($0) ?? 0) }) { raw in
                set(Int(raw) ?? 0)
            }
        }
    }
}

struct DriveScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let drive = model.photo.drive
        DimPage(title: "Drive", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Release", value: "USB", hint: "Sync is the 10-pin pulse. Later.") {
                    ChipRow(options: [("usb", "USB"), ("sync", "Sync")], selected: "usb") { _ in }
                }
                RowBlock(title: "Save", value: drive.save) {
                    ChipRow(options: [("ipad", UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"), ("both", "Both"), ("cards", "Cards")], selected: drive.save) { value in
                        model.edit { $0.drive.save = value }
                    }
                }
                RowBlock(title: "File", value: drive.quality) {
                    ChipRow(options: Catalog.quality.map { ($0.0, $0.1) }, selected: drive.quality) { value in
                        model.edit { $0.drive.quality = value }
                    }
                }
                RowBlock(title: "Timer", value: drive.timer == 0 ? "Off" : "\(drive.timer) s") {
                    ChipRow(options: Catalog.timers.map { ("\($0)", $0 == 0 ? "Off" : "\($0) s") }, selected: "\(drive.timer)") { value in
                        model.edit { $0.drive.timer = Int(value) ?? 0 }
                    }
                }
                RowBlock(title: "Review", value: drive.review == 0 ? "Off" : "\(drive.review) s") {
                    ChipRow(options: Catalog.reviews.map { ("\($0)", $0 == 0 ? "Off" : "\($0) s") }, selected: "\(drive.review)") { value in
                        model.edit { $0.drive.review = Int(value) ?? 0 }
                    }
                }
                RowBlock(title: "Stitch", value: drive.autoStitch ? "After the shot" : "Hold") {
                    ChipRow(options: [("1", "Auto"), ("0", "Hold")], selected: drive.autoStitch ? "1" : "0") { value in
                        model.edit { $0.drive.autoStitch = value == "1" }
                    }
                }
                RowBlock(title: "Engine", value: drive.engine) {
                    ChipRow(options: Catalog.engines.map { ($0.0, $0.1) }, selected: drive.engine) { value in
                        model.edit { $0.drive.engine = value }
                    }
                }
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 8) {
                Text("Hugin fits a small rotation and scale in the overlap, then blends in five bands. A miss feathers the rig overlap.")
                    .font(Theme.font(14))
                    .foregroundStyle(Theme.ink2)
                Text("Match only shifts. Blend and cut use the rig percentage.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
            }
        })
    }
}

struct WBScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "White balance", controls: {
            RowBlock(title: "WB", value: Catalog.wbRow(model.photo.wb).1) {
                ChipRow(options: Catalog.wb.map { ($0.0, $0.1) }, selected: model.photo.wb) { value in
                    model.edit { $0.wb = value }
                }
            }
        }, panel: { PanoFrame(showGuide: false).frame(maxHeight: 320) })
    }
}

struct ModesScreen: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""

    var body: some View {
        DimPage(title: "Modes", controls: {
            VStack(spacing: 8) {
                HStack {
                    TextField("Morning light", text: $name)
                        .textFieldStyle(.plain)
                        .font(Theme.font(16))
                        .padding(10)
                        .background(Theme.s2, in: RoundedRectangle(cornerRadius: 8))
                    Button("New") {
                        model.saveMode(name: name)
                        name = ""
                    }
                    .buttonStyle(GoldButton())
                }
                ForEach(model.modes) { mode in
                    let on = mode.id == model.activeModeID
                    Button { Task { await model.recall(mode) } } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.name).font(Theme.font(16, weight: .medium))
                                Text(modeLine(mode))
                                    .font(Theme.font(12))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(2)
                            }
                            Spacer()
                            if on { Image(systemName: "checkmark").foregroundStyle(Theme.gold) }
                        }
                        .padding(12)
                        .background(on ? Theme.goldDim : Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(on ? Theme.gold : Theme.hair, lineWidth: 1))
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) { model.deleteMode(mode.id) }
                    }
                }
            }
        }, panel: {
            Text("A mode is the whole setup: frame, light, focus, look, drive, and white balance.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.ink2)
        })
    }

    private func modeLine(_ mode: NamedMode) -> String {
        let p = mode.photo
        return "\(Catalog.format(p.frame.squeeze).1) · \(Catalog.fmtISO(p.light.iso)) · \(LookBook.name(p.look))"
    }
}

struct PlaybackScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "Playback", controls: {
            if model.shots.isEmpty {
                Text("No sets yet").foregroundStyle(Theme.dim).padding(.top, 24)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                    ForEach(model.shots) { shot in
                        Button { model.go(.shot(shot.stamp)) } label: { card(shot) }
                    }
                }
            }
        }, panel: { EmptyView() })
    }

    private func card(_ shot: ShotFiles) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Theme.s2
                PairPicture(shot: shot, rig: model.rig, squeeze: model.photo.frame.squeeze)
            }
            .frame(height: 88)
            .clipped()
            Text(shot.name).font(Theme.font(14, weight: .medium))
            Text(state(shot)).font(Theme.font(12)).foregroundStyle(Theme.dim)
        }
        .padding(8)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func state(_ shot: ShotFiles) -> String {
        if shot.stamp == model.stitchingStamp && shot.pano == nil { return "Stitching" }
        if model.stitchWaiting.contains(shot.stamp) && shot.pano == nil { return "Queued" }
        if shot.pano != nil { return model.notes[shot.stamp]?.look ?? "Stitched" }
        if shot.ready { return "Not stitched" }
        return shot.t == nil ? "T missing" : "R missing"
    }
}

struct ShotScreen: View {
    @Environment(AppModel.self) private var model
    var stamp: String
    @State private var part = "pano"

    var body: some View {
        let shot = model.shots.first { $0.stamp == stamp }
        let choices = parts(shot)
        let selected = choices.contains(where: { $0.0 == part }) ? part : (choices.first?.0 ?? "pano")
        DimPage(title: shot?.name ?? stamp, crumb: "Playback", controls: {
            VStack(alignment: .leading, spacing: 12) {
                ChipRow(options: choices, selected: selected) { part = $0 }
                if let shot {
                    fact("Status", status(shot))
                    fact("Stitch", FrameFacts.stitch(stamp))
                    fact("T", FrameFacts.exposure(shot.t))
                    fact("R", FrameFacts.exposure(shot.r))
                }
                if let note = model.notes[stamp] {
                    fact("Mode", note.modeName.isEmpty ? "—" : note.modeName)
                    fact("Look", note.look.isEmpty ? "Standard" : note.look)
                }
                HStack {
                    Button(model.protectedStamps.contains(stamp) ? "Unlock" : "Protect") { model.protect(stamp) }
                        .buttonStyle(PlainChip())
                    Button("Restitch") { model.restitch(stamp) }
                        .buttonStyle(PlainChip())
                    Button("Delete") { model.deleteShot(stamp); model.back() }
                        .buttonStyle(PlainChip())
                }
                if let url = shareURL(shot, part: selected) {
                    ShareLink(item: url) { Text("Share") }
                        .buttonStyle(GoldButton())
                }
            }
        }, panel: {
            if let shot {
                ShotPart(shot: shot, part: selected, rig: model.rig, squeeze: model.photo.frame.squeeze)
            } else {
                Text("Missing file").foregroundStyle(Theme.dim)
            }
        })
    }

    private func parts(_ shot: ShotFiles?) -> [(String, String)] {
        guard let shot else { return [("pano", "Pano")] }
        var rows: [(String, String)] = []
        if shot.pano != nil || shot.ready { rows.append(("pano", "Pano")) }
        if shot.ana != nil { rows.append(("ana", "Ana")) }
        if shot.r != nil { rows.append(("r", "R")) }
        if shot.t != nil { rows.append(("t", "T")) }
        return rows.isEmpty ? [("pano", "Pano")] : rows
    }

    private func status(_ shot: ShotFiles) -> String {
        if shot.stamp == model.stitchingStamp { return "Stitching" }
        if model.stitchWaiting.contains(shot.stamp) { return "Queued" }
        if shot.pano != nil { return "Stitched" }
        if shot.ready { return "Not stitched" }
        return shot.t == nil ? "T missing" : "R missing"
    }

    private func shareURL(_ shot: ShotFiles?, part: String) -> URL? {
        guard let shot else { return nil }
        switch part {
        case "t": return shot.t
        case "r": return shot.r
        case "ana": return shot.ana
        default: return shot.pano ?? shot.ana ?? shot.t
        }
    }

    private func fact(_ name: String, _ value: String) -> some View {
        HStack {
            Text(name.uppercased())
                .font(Theme.font(11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Theme.dim)
                .frame(width: 64, alignment: .leading)
            Text(value).font(Theme.font(14))
            Spacer(minLength: 0)
        }
    }
}

enum FrameFacts {
    static func exposure(_ url: URL?) -> String {
        guard let url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return "—" }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        var bits: [String] = []
        if let iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [NSNumber])?.first {
            bits.append("ISO \(iso)")
        }
        if let time = exif[kCGImagePropertyExifExposureTime] as? Double, time > 0 {
            bits.append(time >= 0.9 ? String(format: "%g s", time) : "1/\(max(1, Int((1 / time).rounded())))")
        }
        if let f = exif[kCGImagePropertyExifFNumber] as? Double, f > 0 {
            bits.append(String(format: "f/%g", f))
        }
        return bits.isEmpty ? "—" : bits.joined(separator: " · ")
    }

    static func stitch(_ stamp: String) -> String {
        let url = Disk.captures.appendingPathComponent("P_\(stamp).json")
        guard let data = try? Data(contentsOf: url),
              let report = try? JSONDecoder().decode(StitchReport.self, from: data) else { return "—" }
        let pct = Int((report.overlap * 100).rounded())
        var text = "\(report.mode) · \(pct)% · dy \(report.dy)\(report.flipR ? " · flop R" : "")"
        if let rot = report.rot {
            text += String(format: " · %+.2f°", rot)
        }
        if let scale = report.scale, abs(scale - 1) >= 0.002 {
            text += String(format: " · ×%.3f", scale)
        }
        if let blend = report.blend {
            text += " · \(blend)"
        }
        return text
    }
}

struct ShotPart: View {
    var shot: ShotFiles
    var part: String
    var rig: Rig
    var squeeze: Double
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: token) {
            let shot = shot
            let part = part
            let rig = rig
            let squeeze = squeeze
            image = await Task.detached(priority: .userInitiated) {
                Self.load(shot, part: part, rig: rig, squeeze: squeeze)
            }.value
        }
    }

    private var token: String {
        "\(part)|\(shot.pano?.path ?? "")|\(shot.t?.path ?? "")|\(shot.r?.path ?? "")|\(shot.ana?.path ?? "")"
    }

    private static func load(_ shot: ShotFiles, part: String, rig: Rig, squeeze: Double) -> UIImage? {
        switch part {
        case "t":
            return shot.t.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1800) }.map { UIImage(cgImage: $0) }
        case "r":
            guard let cg = shot.r.flatMap({ Stitcher.thumbnail(at: $0, maxPixel: 1800) }) else { return nil }
            return UIImage(cgImage: rig.flipR ? Stitcher.flop(cg) : cg)
        case "ana":
            return shot.ana.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1800) }.map { UIImage(cgImage: $0) }
        default:
            if let cg = shot.pano.flatMap({ Stitcher.thumbnail(at: $0, maxPixel: 1800) }) {
                return UIImage(cgImage: cg)
            }
            let t = shot.t.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1400) }
            let r = shot.r.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1400) }
            if let t, let r, let cg = Stitcher.preview(t: t, r: r, rig: rig, squeeze: squeeze, maxWidth: 1600) {
                return UIImage(cgImage: cg)
            }
            return (t ?? r).map { UIImage(cgImage: $0) }
        }
    }
}

struct SystemScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let _ = model.cameraRevision
        DimPage(title: "System", controls: {
            VStack(spacing: 8) {
                nav("Cameras", model.camera.line, .cameras)
                nav("Rig", "\(Int((model.rig.overlap * 100).rounded()))%\(model.rig.flipR ? " · flop R" : "")", .rig)
                nav("Display", model.idleMinutes == 0 ? "Awake" : "\(model.idleMinutes) min", .display)
                nav("Storage", Disk.freeBytes().map(Disk.fmtBytes) ?? "", .storage)
                nav("About", "FXPAN", .about)
                Toggle(isOn: Binding(get: { model.simulate }, set: { model.setSimulate($0) })) {
                    VStack(alignment: .leading) {
                        Text("Simulator").font(Theme.font(16, weight: .medium))
                        Text("Fake D800 pair, no USB").font(Theme.font(12)).foregroundStyle(Theme.dim)
                    }
                }
                .tint(Theme.gold)
                .padding(12)
                .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.camera.line).font(Theme.font(16, weight: .medium))
                Text("T sees through the plate, R off its face.")
                    .font(Theme.font(13)).foregroundStyle(Theme.dim)
            }
        })
    }

    private func nav(_ title: String, _ value: String, _ route: Route) -> some View {
        HStack {
            Text(title).font(Theme.font(16, weight: .medium))
            Spacer()
            Text(value).foregroundStyle(Theme.dim).lineLimit(1)
            Image(systemName: "chevron.right").foregroundStyle(Theme.faint).font(.system(size: 12, weight: .semibold))
        }
        .padding(14)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
        .highPriorityGesture(TapGesture().onEnded { model.go(route) })
    }
}

struct CamerasScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let _ = model.cameraRevision
        DimPage(title: "Cameras", crumb: "System", controls: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tap T or R on each body. A real serial is remembered across a replug. A run of zeros is ignored and that body is paired by its USB port.")
                    .font(Theme.font(13)).foregroundStyle(Theme.dim)
                if model.camera.detected.isEmpty && !model.simulate {
                    Text(model.camera.controlAuthorized ? "Plug both bodies into a powered hub. USB mode MTP/PTP." : "Allow camera control in Settings.")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.ink2)
                }
                ForEach(model.camera.detected) { cam in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cam.model.isEmpty ? "Nikon" : cam.model).font(Theme.font(16, weight: .medium))
                        Text(cam.serial.isEmpty ? "No serial · USB port \(cam.token.drop { $0 != "-" }.dropFirst())" : "#\(cam.serial)")
                            .font(Theme.font(12)).foregroundStyle(Theme.dim)
                        HStack {
                            PressChip(title: "T", on: cam.role == .t, filled: false) { model.pair(cam.token, role: .t) }
                            PressChip(title: "R", on: cam.role == .r, filled: false) { model.pair(cam.token, role: .r) }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(cam.role == nil ? Theme.hair : Theme.gold, lineWidth: 1))
                }
                HStack {
                    PressChip(title: "Swap T and R", filled: false) { model.swap() }
                    PressChip(title: "Clear", filled: false) { model.clearPair(.t); model.clearPair(.r) }
                }
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 8) {
                slot(.t)
                slot(.r)
            }
        })
    }

    private func slot(_ role: Role) -> some View {
        let s = model.camera.slots[role] ?? BodyState()
        return HStack {
            Text(role.rawValue).foregroundStyle(role == .t ? Theme.transmit : Theme.reflect).font(Theme.font(16, weight: .semibold))
            Text(s.online ? s.model : (s.paired ? "paired, off USB" : "open"))
                .foregroundStyle(Theme.ink2)
            Spacer()
            Text(s.serial.isEmpty ? "" : "#\(s.serial.suffix(4))").foregroundStyle(Theme.dim).font(Theme.font(12))
        }
    }
}

struct RigScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "Rig", crumb: "System", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Overlap", value: "\(Int((model.rig.overlap * 100).rounded()))%", hint: "D800 7360×4912 uses 22% when this stays at 20%.") {
                    Ruler(values: Array(stride(from: 10, through: 40, by: 2)).map { "\($0)" }, selected: "\(Int((model.rig.overlap * 100).rounded()))", label: { "\($0)%" }) { value in
                        model.editRig { $0.overlap = (Double(value) ?? 20) / 100 }
                    }
                }
                RowBlock(title: "Flop R", value: model.rig.flipR ? "On" : "Off") {
                    ChipRow(options: [("1", "Flop R"), ("0", "As shot")], selected: model.rig.flipR ? "1" : "0") { value in
                        model.editRig { $0.flipR = value == "1" }
                    }
                }
                RowBlock(title: "Balance", value: model.rig.balance ? "Overlap" : "Off", hint: "Scale R so the shared strip matches T") {
                    ChipRow(options: [("1", "Balance"), ("0", "Off")], selected: model.rig.balance ? "1" : "0") { value in
                        model.editRig { $0.balance = value == "1" }
                    }
                }
            }
        }, panel: { PanoFrame(showGuide: false).frame(maxHeight: 280) })
    }
}

struct DisplayScreen: View {
    @Environment(AppModel.self) private var model
    @State private var bright = UIScreen.main.brightness

    var body: some View {
        DimPage(title: "Display", crumb: "System", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Brightness", value: "\(Int(bright * 100))%") {
                    Slider(value: $bright, in: 0.05...1) { _ in
                        UIScreen.main.brightness = bright
                    }
                    .tint(Theme.gold)
                }
                RowBlock(title: "Sleep", value: model.idleMinutes == 0 ? "Awake" : "\(model.idleMinutes) min") {
                    ChipRow(options: [("0", "Awake"), ("2", "2 min"), ("5", "5 min"), ("10", "10 min")], selected: "\(model.idleMinutes)") { value in
                        model.setIdle(Int(value) ?? 0)
                    }
                }
            }
        }, panel: {
            Text("This is the \(UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad") backlight, not the Pi HDMI panel.")
                .font(Theme.font(14)).foregroundStyle(Theme.dim)
        })
    }
}

struct StorageScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "Storage", crumb: "System", controls: {
            VStack(alignment: .leading, spacing: 12) {
                Text(Disk.freeBytes().map { Disk.fmtBytes($0) + " free" } ?? "—")
                    .font(Theme.font(22, weight: .medium))
                Text("\(model.shots.count) sets in FXPAN")
                    .foregroundStyle(Theme.dim)
                Text("Files are T_, R_, and P_ plus a JSON sidecar, same names as the Pi.")
                    .font(Theme.font(13)).foregroundStyle(Theme.ink2)
                if let latest = model.shots.first?.pano {
                    ShareLink(item: latest) { Text("Share latest panorama") }
                        .buttonStyle(GoldButton())
                }
            }
        }, panel: { EmptyView() })
    }
}

struct AboutScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        DimPage(title: "About", crumb: "System", controls: {
            VStack(alignment: .leading, spacing: 10) {
                Text("FXPAN")
                    .font(Theme.font(28, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                Text("Two Nikons, one 65:24 frame. PTP over a USB hub, stitch on this \(UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad").")
                    .font(Theme.font(15))
                Text("The 10-pin sync release is not in this build.")
                    .font(Theme.font(13)).foregroundStyle(Theme.dim)
                if !model.messages.isEmpty {
                    Text("Recent").font(Theme.font(12, weight: .semibold)).foregroundStyle(Theme.dim).padding(.top, 8)
                    ForEach(model.messages.prefix(8), id: \.self) { line in
                        Text(line).font(Theme.font(13)).foregroundStyle(Theme.ink2)
                    }
                }
            }
        }, panel: { EmptyView() })
    }
}
