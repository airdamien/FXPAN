import ImageIO
import SwiftUI

private struct GuideRowKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct FrameScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.halfOpen) private var halfOpen
    @State private var guideRow: CGFloat = 0

    var body: some View {
        DimPage(title: "Frame", controls: {
            if halfOpen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        formatBlock(fill: rowFill)
                        guideBlock
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(key: GuideRowKey.self, value: geo.size.height)
                                }
                            }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        edgesBlock(fill: rowFill)
                        overlapBlock(fill: rowFill)
                    }
                }
                .onPreferenceChange(GuideRowKey.self) { guideRow = $0 }
            } else {
                VStack(spacing: 10) {
                    formatBlock()
                    guideBlock
                    edgesBlock()
                }
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 12) {
                LivePanel { PanoFrame().frame(maxHeight: 280) }
                FrameSketch(
                    aspect: Catalog.nativeAspect * max(model.photo.frame.squeeze, 1),
                    guide: Catalog.guide(model.photo.frame.guide).1,
                    overlap: model.rig.overlap
                )
                Text("Two frames, \(Int((model.rig.overlap * 100).rounded()))% overlap, one \(Catalog.format(model.photo.frame.squeeze).1) strip")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
            }
        })
    }

    private var rowFill: CGFloat? { guideRow > 1 ? guideRow : nil }

    private func formatBlock(fill: CGFloat? = nil) -> some View {
        RowBlock(title: "Format", value: Catalog.format(model.photo.frame.squeeze).1, fillHeight: fill) {
            ChipRow(options: Catalog.formats.map { (String($0.0), $0.1) }, selected: String(Catalog.format(model.photo.frame.squeeze).0)) { value in
                model.edit { $0.frame.squeeze = Double(value) ?? 1 }
            }
        }
    }

    private var guideBlock: some View {
        RowBlock(title: "Guide", value: Catalog.guide(model.photo.frame.guide).2, hint: "Frame lines to compose inside") {
            ChipRow(options: Catalog.guides.map { ($0.0, $0.2) }, selected: model.photo.frame.guide) { value in
                model.edit { $0.frame.guide = value }
            }
        }
    }

    private func edgesBlock(fill: CGFloat? = nil) -> some View {
        RowBlock(title: "Edges", value: model.photo.frame.clip ? "Clip to aligned" : "Full canvas", hint: "After alignment", fillHeight: fill) {
            ChipRow(options: [("1", "Clip to aligned"), ("0", "Full canvas")], selected: model.photo.frame.clip ? "1" : "0") { value in
                model.edit { $0.frame.clip = value == "1" }
            }
        }
    }

    private func overlapBlock(fill: CGFloat? = nil) -> some View {
        let pct = Int((model.rig.overlap * 100).rounded())
        return RowBlock(title: "Overlap", value: "\(pct)%", hint: "R on the left, T on the right", fillHeight: fill) {
            EmptyView()
        }
    }
}

/// The stitched strip, with each body and the guide crop in the same proportions as the picture.
struct FrameSketch: View {
    var aspect: Double
    var guide: Double
    var overlap: Double

    var body: some View {
        GeometryReader { geo in
            let canvas = CGSize(width: max(0, geo.size.width - 2), height: max(0, geo.size.height - 2))
            let pano = GuideFit.image(in: canvas, aspect: aspect, bottomInset: 0).offsetBy(dx: 1, dy: 1)
            let span = max(0.1, 2 - overlap)
            let unit = pano.width / span
            let rRect = CGRect(x: pano.minX, y: pano.minY, width: unit, height: pano.height)
            let tRect = CGRect(x: pano.minX + unit * (1 - overlap), y: pano.minY, width: unit, height: pano.height)
            let crop = GuideFit.crop(in: pano, ratio: guide)
            ZStack {
                Path { $0.addRect(pano) }.fill(Color.black)
                Path { $0.addRect(rRect) }.stroke(Theme.reflect, lineWidth: 1.5)
                Path { $0.addRect(tRect) }.stroke(Theme.transmit, lineWidth: 1.5)
                if guide > 0 {
                    Path { $0.addRect(crop) }.stroke(Theme.gold, lineWidth: 1)
                }
                Text("R")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.reflect)
                    .position(x: rRect.minX + 16, y: rRect.midY)
                Text("T")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.transmit)
                    .position(x: tRect.maxX - 16, y: tRect.midY)
            }
        }
        .frame(height: 88)
    }
}

private struct ShutterRowKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct LightScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.halfOpen) private var halfOpen
    @State private var shutterRow: CGFloat = 0

    var body: some View {
        let _ = model.cameraRevision
        DimPage(title: "Light", controls: {
            if halfOpen {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        bodyLine(.t)
                        bodyLine(.r)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        isoBlock(hint: false, fill: rowFill)
                        shutterBlock
                            .background {
                                GeometryReader { geo in
                                    Color.clear.preference(key: ShutterRowKey.self, value: geo.size.height)
                                }
                            }
                    }
                    HStack(alignment: .top, spacing: 8) {
                        apertureBlock(hint: false, fill: rowFill)
                        meterBlock(fill: rowFill)
                    }
                    HStack(alignment: .top, spacing: 8) {
                        modeBlock(fill: rowFill)
                        masterBlock(fill: rowFill)
                    }
                    Text(model.camera.line).font(Theme.font(13)).foregroundStyle(Theme.dim)
                }
                .onPreferenceChange(ShutterRowKey.self) { shutterRow = $0 }
            } else {
                VStack(spacing: 10) {
                    modeBlock()
                    isoBlock()
                    shutterBlock
                    apertureBlock()
                    masterBlock()
                    meterBlock()
                }
            }
        }, panel: {
            if halfOpen {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    bodyLine(.t)
                    bodyLine(.r)
                    Text(model.camera.line).font(Theme.font(13)).foregroundStyle(Theme.dim)
                }
            }
        })
    }

    /// Height of the shutter card. The other control cards use it so every row matches.
    private var rowFill: CGFloat? { shutterRow > 1 ? shutterRow : nil }

    private func modeBlock(fill: CGFloat? = nil) -> some View {
        let light = model.photo.light
        return RowBlock(title: "Mode", value: light.program, fillHeight: fill) {
            ChipRow(options: Catalog.programs.map { ($0.0, $0.0) }, selected: light.program) { value in
                model.edit { $0.light.program = value }
            }
        }
    }

    private func isoBlock(hint: Bool = true, fill: CGFloat? = nil) -> some View {
        let light = model.photo.light
        return RowBlock(title: "ISO", value: Catalog.fmtISO(light.iso), hint: hint ? (light.followCam ? "Camera decides" : "Both bodies") : "", fillHeight: fill) {
            Ruler(values: Catalog.iso, selected: light.iso, label: { Catalog.isAuto($0) ? "Auto" : $0 }) { value in
                model.edit { $0.light.iso = value }
            }
        }
    }

    private var shutterBlock: some View {
        let light = model.photo.light
        return RowBlock(title: "Shutter", value: Catalog.fmtShut(light.shutter)) {
            Ruler(values: Catalog.shutter, selected: light.shutter, label: Catalog.fmtShut) { value in
                model.edit { $0.light.shutter = value }
            }
        }
    }

    private func apertureBlock(hint: Bool = true, fill: CGFloat? = nil) -> some View {
        let light = model.photo.light
        return RowBlock(title: "Aperture", value: Catalog.fmtF(light.fstop), hint: hint ? "Taking-lens iris" : "", fillHeight: fill) {
            Ruler(values: Catalog.fstop, selected: light.fstop, label: { Catalog.isAuto($0) ? "Auto" : $0 }) { value in
                model.edit { $0.light.fstop = value }
            }
        }
    }

    private func masterBlock(fill: CGFloat? = nil) -> some View {
        let light = model.photo.light
        return RowBlock(title: "Master", value: light.master, fillHeight: fill) {
            ChipRow(options: [("T", "T"), ("R", "R")], selected: light.master) { value in
                model.edit { $0.light.master = value }
            }
        }
    }

    private func meterBlock(fill: CGFloat? = nil) -> some View {
        let light = model.photo.light
        return RowBlock(title: "Meter", value: light.followCam ? "Camera" : "FXPAN", fillHeight: fill) {
            ChipRow(options: [("0", "Set from here"), ("1", "Camera decides")], selected: light.followCam ? "1" : "0") { value in
                model.edit { $0.light.followCam = value == "1" }
            }
        }
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
    @Environment(\.halfOpen) private var halfOpen
    var body: some View {
        DimPage(title: "Focus", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Aid", value: model.photo.focus.aid, hint: "The box sits on the sharp part of the panorama. Tap the picture to watch one place, and tap that box again to follow the sharp part. Range shortens the arrow while that place gets sharper, and jumps across when you pass the sharp point.") {
                    ChipRow(options: [("off", "Off"), ("peaking", "Peaking"), ("loupe", "Loupe"), ("range", "Range")], selected: model.photo.focus.aid) { value in
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
                if model.simulate, !halfOpen {
                    Text(model.playingFocus ? "Playing the blur" : "Play focus")
                        .font(Theme.font(15, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.s2, in: RoundedRectangle(cornerRadius: Theme.radius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.gold, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: Theme.radius))
                        .highPriorityGesture(TapGesture().onEnded {
                            guard !model.playingFocus else { return }
                            Task { await model.playFocus() }
                        })
                }
            }
        }, panel: { LivePanel { PanoFrame().frame(maxHeight: 320) } })
    }
}

struct LookScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let look = model.photo.look
        DimPage(title: "Look", controls: {
            VStack(spacing: 10) {
                RowBlock(title: "Base", value: LookBook.names.first { $0.0 == look.base }?.1 ?? "Off", hint: LookBook.names.contains { $0.0 == look.base } ? LookBook.note(look) : "") {
                    ChipRow(options: LookBook.names.map { ($0.0, $0.1) }, selected: look.base) { value in
                        model.edit {
                            $0.look.base = value
                            $0.look.id = value
                        }
                    }
                }
                RowBlock(title: "Film", value: LookBook.films.first { $0.0 == look.base }?.1 ?? "Off", hint: LookBook.films.contains { $0.0 == look.base } ? LookBook.note(look) : "A hue map and a tone curve, the way a medium-format body recalls a film stock.") {
                    ChipRow(options: [("off", "Off")] + LookBook.films.map { ($0.0, $0.1) }, selected: LookBook.films.contains { $0.0 == look.base } ? look.base : "off") { value in
                        let next = LookBook.pickFilm(look.base, value)
                        model.edit {
                            $0.look.base = next
                            $0.look.id = next
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
        }, panel: { LivePanel { PanoFrame(showGuide: false).frame(maxHeight: 320) } })
    }

    private func stepper(_ title: String, _ value: Int, _ set: @escaping (Int) -> Void) -> some View {
        RowBlock(title: title, value: Catalog.signed(value)) {
            Ruler(values: LookBook.steps.map(String.init), selected: String(value), label: { Catalog.signed(Int($0) ?? 0) }) { raw in
                set(Int(raw) ?? 0)
            }
        }
    }
}

private struct DriveRowKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct DriveScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.halfOpen) private var halfOpen
    @State private var driveRow: CGFloat = 0

    var body: some View {
        let drive = model.photo.drive
        DimPage(title: "Drive", controls: {
            if halfOpen {
                VStack(alignment: .leading, spacing: 8) {
                    pair(releaseBlock(fill: rowFill, compact: true), timerBlock(fill: rowFill))
                    pair(
                        fileBlock.background {
                            GeometryReader { geo in
                                Color.clear.preference(key: DriveRowKey.self, value: geo.size.height)
                            }
                        },
                        developBlock(fill: rowFill, compact: true)
                    )
                    pair(saveBlock(fill: rowFill), reviewBlock(fill: rowFill))
                    pair(stitchBlock(fill: rowFill), engineBlock(fill: rowFill))
                    if drive.ciraw {
                        pair(lensBlock(fill: rowFill, compact: true), overlapNote(fill: rowFill))
                    }
                }
                .onPreferenceChange(DriveRowKey.self) { driveRow = $0 }
            } else {
                VStack(spacing: 10) {
                    releaseBlock().task { await model.probeSync() }
                    saveBlock()
                    fileBlock
                    developBlock()
                    if drive.ciraw { lensBlock() }
                    timerBlock()
                    reviewBlock()
                    stitchBlock()
                    engineBlock()
                }
            }
        }, panel: {
            if halfOpen {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hugin fits a small rotation and scale in the overlap, then blends in bands sized to the overlap. A miss feathers the rig overlap.")
                        .font(Theme.font(14))
                        .foregroundStyle(Theme.ink2)
                    Text("Match only shifts. Blend and cut use the rig percentage.")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                }
            }
        })
        .task { await model.probeSync() }
    }

    private var rowFill: CGFloat? { driveRow > 1 ? driveRow : nil }

    private func pair<A: View, B: View>(_ leading: A, _ trailing: B) -> some View {
        HStack(alignment: .top, spacing: 8) {
            leading.frame(maxWidth: .infinity, alignment: .top)
            trailing.frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func releaseBlock(fill: CGFloat? = nil, compact: Bool = false) -> some View {
        let drive = model.photo.drive
        let value = drive.release == "sync" ? (model.syncReady ? "Sync" : "Sync · waiting") : "USB"
        return RowBlock(title: "Release", value: value, hint: compact ? "" : "Sync drops USB, pulses the 10-pin board, then downloads the frame from camera RAM.", fillHeight: fill) {
            ChipRow(options: [("usb", "USB"), ("sync", "Sync")], selected: drive.release) { value in
                model.edit { $0.drive.release = value }
            }
        }
    }

    private func saveBlock(fill: CGFloat? = nil) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Save", value: drive.save, fillHeight: fill) {
            ChipRow(options: [("ipad", UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"), ("both", "Both"), ("cards", "Cards")], selected: drive.save) { value in
                model.edit { $0.drive.save = value }
            }
        }
    }

    private var fileBlock: some View {
        let drive = model.photo.drive
        return RowBlock(title: "File", value: drive.quality) {
            ChipRow(options: Catalog.quality.map { ($0.0, $0.1) }, selected: drive.quality) { value in
                model.edit { $0.drive.quality = value }
            }
        }
    }

    private func developBlock(fill: CGFloat? = nil, compact: Bool = false) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Develop", value: drive.ciraw ? "CIRAW" : "JPEG", hint: compact ? "" : "CIRAW opens the NEF and recovers highlights. The Apple mode also runs local tone, noise, and detail. No NEF uses the JPEG.", fillHeight: fill) {
            ChipRow(options: [("0", "JPEG"), ("1", "CIRAW")], selected: drive.ciraw ? "1" : "0") { value in
                model.edit { $0.drive.ciraw = value == "1" }
            }
        }
    }

    private func lensBlock(fill: CGFloat? = nil, compact: Bool = false) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Lens", value: drive.cirawLens ? "Corrected" : "Off", hint: compact ? "" : "Apple's lens correction. Off keeps the overlap you already tuned.", fillHeight: fill) {
            ChipRow(options: [("0", "Off"), ("1", "Correct")], selected: drive.cirawLens ? "1" : "0") { value in
                model.edit { $0.drive.cirawLens = value == "1" }
            }
        }
    }

    private func overlapNote(fill: CGFloat? = nil) -> some View {
        RowBlock(title: "Overlap", value: "Kept", hint: "Correction off leaves the rig overlap alone.", fillHeight: fill) {
            EmptyView()
        }
    }

    private func timerBlock(fill: CGFloat? = nil) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Timer", value: drive.timer == 0 ? "Off" : "\(drive.timer) s", fillHeight: fill) {
            ChipRow(options: Catalog.timers.map { ("\($0)", $0 == 0 ? "Off" : "\($0) s") }, selected: "\(drive.timer)") { value in
                model.edit { $0.drive.timer = Int(value) ?? 0 }
            }
        }
    }

    private func reviewBlock(fill: CGFloat? = nil) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Review", value: drive.review == 0 ? "Off" : "\(drive.review) s", fillHeight: fill) {
            ChipRow(options: Catalog.reviews.map { ("\($0)", $0 == 0 ? "Off" : "\($0) s") }, selected: "\(drive.review)") { value in
                model.edit { $0.drive.review = Int(value) ?? 0 }
            }
        }
    }

    private func stitchBlock(fill: CGFloat? = nil) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Stitch", value: drive.autoStitch ? "After the shot" : "Hold", fillHeight: fill) {
            ChipRow(options: [("1", "Auto"), ("0", "Hold")], selected: drive.autoStitch ? "1" : "0") { value in
                model.edit { $0.drive.autoStitch = value == "1" }
            }
        }
    }

    private func engineBlock(fill: CGFloat? = nil) -> some View {
        let drive = model.photo.drive
        return RowBlock(title: "Engine", value: drive.engine, fillHeight: fill) {
            ChipRow(options: Catalog.engines.map { ($0.0, $0.1) }, selected: drive.engine) { value in
                model.edit { $0.drive.engine = value }
            }
        }
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
        }, panel: { LivePanel { PanoFrame(showGuide: false).frame(maxHeight: 320) } })
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
        var line = "\(Catalog.format(p.frame.squeeze).1) · \(Catalog.fmtISO(p.light.iso)) · \(LookBook.name(p.look))"
        if p.drive.ciraw { line += " · CIRAW" }
        return line
    }
}

struct PlaybackScreen: View {
    @Environment(AppModel.self) private var model
    @State private var confirmAll = false
    @State private var confirmOlder = false

    var body: some View {
        DimPage(title: "Playback", controls: {
            if model.shots.isEmpty {
                Text("No sets yet").foregroundStyle(Theme.dim).padding(.top, 24)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        PressChip(title: "Delete all", filled: false) { confirmAll = true }
                            .confirmationDialog("Delete every set?", isPresented: $confirmAll, titleVisibility: .visible) {
                                Button("Delete all", role: .destructive) { model.deleteShots(beforeToday: false) }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Protected sets stay.")
                            }
                        PressChip(title: "Older than today", filled: false) { confirmOlder = true }
                            .confirmationDialog("Delete sets from before today?", isPresented: $confirmOlder, titleVisibility: .visible) {
                                Button("Delete older", role: .destructive) { model.deleteShots(beforeToday: true) }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Protected sets stay.")
                            }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                        ForEach(model.shots) { shot in
                            card(shot)
                                .onTapGesture { model.go(.shot(shot.stamp)) }
                                .onLongPressGesture(minimumDuration: 0.35) {
                                    model.peep(shot.ana ?? shot.pano ?? shot.t ?? shot.r, title: shot.name)
                                }
                        }
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
        if shot.stamp == model.stitchingStamp && shot.pano == nil { return model.stitchLabel ?? "Stitching" }
        if model.stitchWaiting.contains(shot.stamp) && shot.pano == nil { return "Queued" }
        if shot.pano != nil {
            let report = FrameFacts.report(shot.stamp)
            let mp = FrameFacts.output(shot, report: report)
            if mp != "—" {
                var bits = [mp]
                if let sec = report?.sec { bits.append(FrameFacts.formatSec(sec)) }
                return bits.joined(separator: " · ")
            }
            return model.notes[shot.stamp]?.look ?? "Stitched"
        }
        if shot.ready { return "Not stitched" }
        return shot.t == nil ? "T missing" : "R missing"
    }
}

struct ShotScreen: View {
    @Environment(AppModel.self) private var model
    var stamp: String
    @State private var part = "pano"
    @State private var styleBase = "standard"
    @State private var styleGrain = "off"
    @State private var styleFilter = "none"
    @State private var styleApple = "off"
    @State private var confirmDelete = false

    private var previewLook: LookSet {
        var look = LookSet()
        look.base = styleBase
        look.id = styleBase
        look.grain = styleGrain
        look.filter = LookBook.isMono(look) ? styleFilter : "none"
        look.apple = styleApple
        return look
    }

    var body: some View {
        let shot = model.shots.first { $0.stamp == stamp }
        let choices = parts(shot)
        let selected = choices.contains(where: { $0.0 == part }) ? part : (choices.first?.0 ?? "pano")
        DimPage(title: shot?.name ?? stamp, crumb: "Playback", stickPanel: true, controls: {
            VStack(alignment: .leading, spacing: 12) {
                ChipRow(options: choices, selected: selected) { part = $0 }
                if let shot {
                    let report = FrameFacts.report(stamp)
                    fact("Status", status(shot))
                    fact("Size", FrameFacts.size(shot, report: report))
                    fact("Output", FrameFacts.output(shot, report: report))
                    fact("Time", report?.sec.map(FrameFacts.formatSec) ?? "—")
                    fact("Stitch", FrameFacts.stitch(report))
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
                    if model.stitchingStamp == stamp || model.stitchWaiting.contains(stamp) {
                        Button("Cancel") { model.cancelStitch() }
                            .buttonStyle(PlainChip())
                    }
                    Button("Delete") { confirmDelete = true }
                        .buttonStyle(PlainChip())
                        .confirmationDialog("Delete this set?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete", role: .destructive) {
                                model.deleteShot(stamp)
                                model.back()
                            }
                            Button("Cancel", role: .cancel) {}
                        }
                }
                ChipRow(options: Catalog.engines.map { ($0.0, $0.1) }, selected: model.photo.drive.engine) { value in
                    model.restitch(stamp, engine: value)
                }
                ChipRow(options: [("jpeg", "JPEG"), ("ciraw", "CIRAW")], selected: model.photo.drive.ciraw ? "ciraw" : "jpeg") { value in
                    model.edit { $0.drive.ciraw = value == "ciraw" }
                    model.restitch(stamp)
                }
                Text("Pick a stitch to run it on this set. Hold the picture to inspect pixels.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
                ChipRow(options: LookBook.names.map { ($0.0, $0.1) }, selected: styleBase) { styleBase = $0 }
                ChipRow(options: [("off", "Off")] + LookBook.films.map { ($0.0, $0.1) }, selected: LookBook.films.contains { $0.0 == styleBase } ? styleBase : "off") { styleBase = LookBook.pickFilm(styleBase, $0) }
                if LookBook.isMono(previewLook) {
                    ChipRow(options: LookBook.filters.map { ($0, $0.prefix(1).uppercased() + $0.dropFirst()) }, selected: styleFilter) { styleFilter = $0 }
                }
                ChipRow(options: LookBook.grains.map { ($0, $0.prefix(1).uppercased() + $0.dropFirst()) }, selected: styleGrain) { styleGrain = $0 }
                ForEach(AppleBook.groups) { group in
                    let chips = AppleBook.options(model.appleEnabled, group: group.id, current: styleApple)
                    if !chips.isEmpty {
                        Text(group.viewer)
                            .font(Theme.font(12))
                            .foregroundStyle(Theme.dim)
                        ChipRow(options: chips, selected: styleApple) { pickApple($0) }
                    }
                }
                Button(model.savingStyle == stamp ? "Saving" : "Save look") {
                    model.saveStyle(stamp, look: previewLook)
                }
                .buttonStyle(GoldButton())
                .disabled(model.savingStyle != nil || model.upscaleLabel != nil || shot?.pano == nil)
                Button(model.upscaleLabel ?? "Upscale") {
                    model.upscale(stamp)
                }
                .buttonStyle(GoldButton())
                .disabled(model.upscaleLabel != nil || model.savingStyle != nil || shot?.pano == nil)
                Text("Save look writes this style onto the panorama. Upscale runs Real-ESRGAN on the subject, in overlapping tiles, and scales the rest of the frame to match. Another tap starts from the original.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
                if let url = shareURL(shot, part: selected) {
                    ShareLink(item: url) { Text("Share") }
                        .buttonStyle(GoldButton())
                }
            }
        }, panel: {
            if let shot {
                ShotPart(shot: shot, part: selected, rig: model.rig, squeeze: model.photo.frame.squeeze, generation: model.stitchGeneration, look: previewLook)
                    .onLongPressGesture(minimumDuration: 0.35) {
                        model.peep(file(shot, part: selected), title: shot.name)
                    }
            } else {
                Text("Missing file").foregroundStyle(Theme.dim)
            }
        })
        .onAppear(perform: restoreStyle)
    }

    private func restoreStyle() {
        guard let note = model.notes[stamp] else { return }
        styleBase = note.styleBase
        styleGrain = note.styleGrain.isEmpty ? "off" : note.styleGrain
        styleFilter = note.styleFilter.isEmpty ? "none" : note.styleFilter
        styleApple = note.styleApple.isEmpty ? "off" : note.styleApple
    }

    private func pickApple(_ id: String) {
        styleApple = id
        model.stageApple(stamp, id)
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
        if shot.stamp == model.stitchingStamp { return model.stitchLabel ?? "Stitching" }
        if model.stitchWaiting.contains(shot.stamp) { return "Queued" }
        if shot.pano != nil { return "Stitched" }
        if shot.ready { return "Not stitched" }
        return shot.t == nil ? "T missing" : "R missing"
    }

    private func shareURL(_ shot: ShotFiles?, part: String) -> URL? {
        file(shot, part: part)
    }

    private func file(_ shot: ShotFiles?, part: String) -> URL? {
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
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(Theme.font(14))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    static func report(_ stamp: String) -> StitchReport? {
        let url = Disk.captures.appendingPathComponent("P_\(stamp).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StitchReport.self, from: data)
    }

    /// The delivered file: the desqueezed ana when there is one, otherwise the panorama.
    static func outputURL(_ shot: ShotFiles) -> URL? {
        shot.ana ?? shot.pano
    }

    static func pixels(_ url: URL?) -> (Int, Int)? {
        guard let url,
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else { return nil }
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let w, let h, w > 0, h > 0 else { return nil }
        return (w, h)
    }

    static func size(_ shot: ShotFiles, report: StitchReport?) -> String {
        if let px = pixels(outputURL(shot)) ?? report.map({ ($0.width, $0.height) }) {
            return "\(px.0.formatted()) × \(px.1.formatted())"
        }
        return "—"
    }

    static func output(_ shot: ShotFiles, report: StitchReport?) -> String {
        if let px = pixels(outputURL(shot)) ?? report.map({ ($0.width, $0.height) }) {
            return megapixels(px.0, px.1)
        }
        return "—"
    }

    static func megapixels(_ width: Int, _ height: Int) -> String {
        let mp = Double(width) * Double(height) / 1_000_000
        return String(format: mp >= 100 ? "%.0f MP" : "%.1f MP", mp)
    }

    static func formatSec(_ sec: Double) -> String {
        if sec < 60 { return String(format: "%.1f s", sec) }
        let minutes = Int(sec) / 60
        let rest = sec - Double(minutes * 60)
        return String(format: "%dm %.0fs", minutes, rest)
    }

    static func stitch(_ report: StitchReport?) -> String {
        guard let report else { return "—" }
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
        if report.develop == "ciraw" {
            text += " · CIRAW"
        }
        return text
    }
}

struct ShotPart: View {
    var shot: ShotFiles
    var part: String
    var rig: Rig
    var squeeze: Double
    var generation: Int
    var look: LookSet
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
            let look = look
            image = await Task.detached(priority: .userInitiated) {
                Self.load(shot, part: part, rig: rig, squeeze: squeeze, look: look)
            }.value
        }
    }

    private var token: String {
        func revised(_ url: URL?) -> String {
            guard let url else { return "" }
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(url.path)#\(modified)"
        }
        return "\(generation)|\(part)|\(look.base)|\(look.grain)|\(look.filter)|\(look.apple)|\(revised(shot.pano))|\(revised(shot.t))|\(revised(shot.r))|\(revised(shot.ana))|\(revised(LookStore.plain(stamp: shot.stamp, ana: false)))|\(revised(LookStore.plain(stamp: shot.stamp, ana: true)))"
    }

    private static func load(_ shot: ShotFiles, part: String, rig: Rig, squeeze: Double, look: LookSet) -> UIImage? {
        let cg: CGImage?
        switch part {
        case "t":
            cg = shot.t.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1800) }
        case "r":
            cg = shot.r.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1800) }.map { rig.flipR ? Stitcher.flop($0) : $0 }
        case "ana":
            cg = (LookStore.plain(stamp: shot.stamp, ana: true) ?? shot.ana).flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1800) }
        default:
            if let pano = (LookStore.plain(stamp: shot.stamp, ana: false) ?? shot.pano).flatMap({ Stitcher.thumbnail(at: $0, maxPixel: 1800) }) {
                cg = pano
            } else {
                let t = shot.t.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1400) }
                let r = shot.r.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1400) }
                if let t, let r, let preview = Stitcher.preview(t: t, r: r, rig: rig, squeeze: squeeze, maxWidth: 1600) {
                    cg = preview
                } else {
                    cg = t ?? r
                }
            }
        }
        guard let cg else { return nil }
        let shown = LookBook.identity(look) ? cg : Stitcher.grade(cg, look: look)
        return UIImage(cgImage: shown)
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
                nav("Apple", appleLine, .apple)
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
                Toggle(isOn: Binding(get: { model.canon }, set: { model.setCanon($0) })) {
                    VStack(alignment: .leading) {
                        Text("Canon").font(Theme.font(16, weight: .medium))
                        Text("One EOS. Live view, shutter, and the file copy.").font(Theme.font(12)).foregroundStyle(Theme.dim)
                    }
                }
                .tint(Theme.gold)
                .padding(12)
                .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 8) {
                Text(model.camera.line).font(Theme.font(16, weight: .medium))
                Text(model.canon
                     ? "USB connection set to photo import. The card is left alone. A CR3 is saved beside the JPEG."
                     : "T sees through the plate, R off its face.")
                    .font(Theme.font(13)).foregroundStyle(Theme.dim)
            }
        })
    }

    private var appleLine: String {
        let gpu = model.metalWarp ? "Metal" : "CPU"
        if model.appleEnabled.isEmpty { return gpu }
        return "\(gpu) · \(model.appleEnabled.count) on"
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

struct AppleScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        DimPage(title: "Apple", crumb: "System", controls: {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { model.metalWarp }, set: { model.setMetalWarp($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Metal warp").font(Theme.font(16, weight: .medium))
                        Text("Samples both frames on the GPU while stitching. Off uses the same bilinear on the CPU.")
                            .font(Theme.font(12)).foregroundStyle(Theme.dim)
                    }
                }
                .tint(Theme.gold)
                .padding(12)
                .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
                Text("Still-image tools that can run on a finished Nikon JPEG. Turn on the ones you want as buttons in playback and on the keep screen.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
                Text("Super-resolution, temporal denoise, and motion blur need a video frame at 1920 pixels or a run of frames. Image Playground draws a new picture. Smart HDR and Deep Fusion stay inside the iPhone camera.")
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.ink2)
                ForEach(AppleBook.groups) { group in
                    self.group(group.title, group.id)
                }
            }
        }, panel: {
            Text("Off leaves the stitch as shot. Save look in playback writes the one you pick.")
                .font(Theme.font(14))
                .foregroundStyle(Theme.dim)
        })
    }

    @ViewBuilder
    private func group(_ title: String, _ id: String) -> some View {
        let rows = AppleBook.effects.filter { $0.group == id }
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(Theme.font(11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.dim)
            ForEach(rows) { effect in
                Toggle(isOn: Binding(
                    get: { model.appleEnabled.contains(effect.id) },
                    set: { model.setApple(effect.id, on: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(effect.title).font(Theme.font(16, weight: .medium))
                        Text(effect.detail).font(Theme.font(12)).foregroundStyle(Theme.dim)
                    }
                }
                .tint(Theme.gold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct CamerasScreen: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        let _ = model.cameraRevision
        DimPage(title: "Cameras", crumb: "System", controls: {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.canon
                     ? "One Canon on USB. Live view and the shutter use remote control. Turn Canon off to use the Nikon pair."
                     : "Tap T or R on each body. A real serial is remembered across a replug. A run of zeros is ignored and that body is paired by its USB port.")
                    .font(Theme.font(13)).foregroundStyle(Theme.dim)
                if model.camera.detected.isEmpty && !model.simulate {
                    Text(model.camera.controlAuthorized
                         ? (model.canon ? "Plug the EOS in. USB connection: photo import / remote control." : "Plug both bodies into a powered hub. USB mode MTP/PTP.")
                         : "Allow camera control in Settings.")
                        .font(Theme.font(15))
                        .foregroundStyle(Theme.ink2)
                }
                ForEach(model.camera.detected) { cam in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(cam.model.isEmpty ? (model.canon ? "Canon" : "Nikon") : cam.model).font(Theme.font(16, weight: .medium))
                        Text(cam.serial.isEmpty ? "No serial · USB port \(cam.token.drop { $0 != "-" }.dropFirst())" : "#\(cam.serial)")
                            .font(Theme.font(12)).foregroundStyle(Theme.dim)
                        if !cam.link.isEmpty {
                            Text(cam.link)
                                .font(Theme.font(12, weight: .medium))
                                .foregroundStyle(Theme.ink2)
                        }
                        if !model.canon {
                            HStack {
                                PressChip(title: "T", on: cam.role == .t, filled: false) { model.pair(cam.token, role: .t) }
                                PressChip(title: "R", on: cam.role == .r, filled: false) { model.pair(cam.token, role: .r) }
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(cam.role == nil && !model.canon ? Theme.hair : Theme.gold, lineWidth: 1))
                }
                if !model.canon {
                    HStack {
                        PressChip(title: "Swap T and R", filled: false) { model.swap() }
                        PressChip(title: "Clear", filled: false) { model.clearPair(.t); model.clearPair(.r) }
                    }
                }
            }
        }, panel: {
            VStack(alignment: .leading, spacing: 10) {
                Text("SEATED")
                    .font(Theme.font(11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.dim)
                seat(.t)
                if !model.canon { seat(.r) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        })
    }

    private func seat(_ role: Role) -> some View {
        let s = model.camera.slots[role] ?? BodyState()
        let tint = role == .t ? Theme.transmit : Theme.reflect
        let name = s.model.isEmpty ? (model.canon ? "Canon" : "Nikon") : s.model
        let state = s.online ? "On USB" : (s.paired ? "Paired, off USB" : "Open")
        let exposure = [s.program, s.iso, s.shutter, s.fstop.isEmpty ? "" : "f/\(s.fstop)"].filter { !$0.isEmpty }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(model.canon ? "EOS" : role.rawValue)
                    .font(Theme.font(28, weight: .medium))
                    .foregroundStyle(tint)
                Text(state)
                    .font(Theme.font(13))
                    .foregroundStyle(s.online ? Theme.ink2 : Theme.dim)
                Spacer()
                if s.online, let pct = s.battery {
                    Text("\(pct)%")
                        .font(Theme.font(13))
                        .foregroundStyle(Theme.dim)
                }
            }
            Text(s.online || s.paired ? name : "No body")
                .font(Theme.font(16, weight: .medium))
            HStack(alignment: .top, spacing: 18) {
                seatFact("Serial", s.serial.isEmpty ? "—" : s.serial)
                seatFact("Link", s.link.isEmpty ? "—" : s.link)
            }
            if s.online, !exposure.isEmpty {
                Text(exposure.joined(separator: " · "))
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(s.paired ? tint.opacity(0.85) : Theme.hair, lineWidth: 1))
    }

    private func seatFact(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(Theme.font(10, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(Theme.faint)
            Text(value)
                .font(Theme.font(13))
                .foregroundStyle(Theme.ink2)
                .lineLimit(1)
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
                RowBlock(title: "Balance", value: model.rig.balance ? "Overlap" : "Off", hint: "Match color in the shared strip, darkening whichever body is brighter") {
                    ChipRow(options: [("1", "Balance"), ("0", "Off")], selected: model.rig.balance ? "1" : "0") { value in
                        model.editRig { $0.balance = value == "1" }
                    }
                }
            }
        }, panel: { LivePanel { PanoFrame(showGuide: false).frame(maxHeight: 280) } })
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
                RowBlock(title: "Sleep", value: model.idleMinutes == 0 ? "Awake" : "\(model.idleMinutes) min", hint: "No touch for this long stops live view and lets the bodies sleep.") {
                    ChipRow(options: [("0", "Awake"), ("2", "2 min"), ("5", "5 min"), ("10", "10 min")], selected: "\(model.idleMinutes)") { value in
                        model.setIdle(Int(value) ?? 0)
                    }
                }
            }
        }, panel: {
            Text("Sleep releases the cameras. Brightness is this \(UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad")'s backlight.")
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
                Text("10-pin sync is the Zero W on the USB gadget at 10.55.0.1. Release set to Sync pulses it.")
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
