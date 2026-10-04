import SwiftUI

enum HomePane {
    case all
    case picture
    case controls
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    var pane: HomePane = .all
    @State private var zoom: CGFloat = 1
    @State private var magnify: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var drag: CGSize = .zero

    private let dims: [(Route, String, String)] = [
        (.frame, "Frame", "rectangle.compress.vertical"),
        (.light, "Light", "sun.max"),
        (.focus, "Focus", "viewfinder"),
        (.look, "Look", "circle.lefthalf.filled"),
        (.drive, "Drive", "timer"),
        (.wb, "WB", "circle.hexagongrid"),
    ]

    var body: some View {
        let _ = model.cameraRevision
        switch pane {
        case .picture:
            fittedFrame(flush: true)
                .frame(maxWidth: .infinity, alignment: .top)
                .background(Color.black)
        case .controls:
            controlsColumn
        case .all:
            arranged
        }
    }

    private var arranged: some View {
        GeometryReader { geo in
            let phone = min(geo.size.width, geo.size.height) <= 500
            let landscape = geo.size.width > geo.size.height
            let wide = landscape && geo.size.width >= 980
            if phone && landscape {
                phoneLandscape
            } else if phone {
                phonePortrait
            } else if wide {
                HStack(spacing: 10) {
                    main
                    railVertical
                        .frame(width: 96)
                }
            } else {
                VStack(spacing: 10) {
                    main
                    railHorizontal
                }
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.bottom, 10)
    }

    /// Tiles and the shutter, without the frame. The book fold keeps the picture on the other screen.
    private var controlsColumn: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(dims, id: \.1) { dim in
                    Button { model.go(dim.0) } label: { tile(dim.1, dim.2, text(dim.1), compact: true) }
                        .frame(minHeight: 86)
                }
            }
            Spacer(minLength: 8)
            railHorizontal
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var phonePortrait: some View {
        VStack(spacing: 8) {
            fittedFrame()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(dims, id: \.1) { dim in
                    Button { model.go(dim.0) } label: { tile(dim.1, dim.2, text(dim.1), compact: true) }
                        .frame(minHeight: 86)
                }
            }
            Spacer(minLength: 12)
            railHorizontal
        }
    }

    private var phoneLandscape: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                fittedFrame()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                railVertical
                    .frame(width: 84)
            }
            HStack(spacing: 6) {
                ForEach(dims, id: \.1) { dim in
                    Button { model.go(dim.0) } label: { tile(dim.1, dim.2, text(dim.1), compact: true) }
                }
            }
            .frame(height: 72)
        }
    }

    /// The picture's own height, with the exposure line under it. The book fold keeps this on the screen above the hinge.
    private func fittedFrame(flush: Bool = false) -> some View {
        frame(flush: flush)
            .frame(maxWidth: .infinity)
    }

    private func frame(flush: Bool = false) -> some View {
        let scale = min(8, max(1, zoom * magnify))
        return ZStack(alignment: .top) {
            PanoFrame(showLiveHint: !model.camera.live && zoom <= 1.02, flush: flush, aiming: zoom <= 1.02)
                .scaleEffect(scale, anchor: .center)
                .offset(x: pan.width + drag.width, y: pan.height + drag.height)
                .gesture(MagnifyGesture()
                    .onChanged { value in magnify = value.magnification }
                    .onEnded { value in
                        zoom = min(8, max(1, zoom * value.magnification))
                        magnify = 1
                        if zoom <= 1.02 {
                            zoom = 1
                            pan = .zero
                            drag = .zero
                        }
                    })
                .simultaneousGesture(DragGesture()
                    .onChanged { value in
                        guard zoom > 1.02 else { return }
                        drag = value.translation
                    }
                    .onEnded { value in
                        guard zoom > 1.02 else { return }
                        pan.width += value.translation.width
                        pan.height += value.translation.height
                        drag = .zero
                    })
                .onTapGesture(count: 2) {
                    zoom = 1
                    magnify = 1
                    pan = .zero
                    drag = .zero
                }
                .onTapGesture {
                    guard zoom <= 1.02 else { return }
                    if model.photo.focus.aid != "off", model.camera.live { return }
                    Task { await model.toggleLive() }
                }
            if model.simulate, model.photo.focus.aid != "off" {
                HStack {
                    Spacer()
                    Text(model.playingFocus ? "Playing" : "Play focus")
                        .font(Theme.font(12, weight: .semibold))
                        .foregroundStyle(Theme.gold)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.black.opacity(0.65), in: Capsule())
                        .contentShape(Capsule())
                        .highPriorityGesture(TapGesture().onEnded {
                            guard !model.playingFocus else { return }
                            Task { await model.playFocus() }
                        })
                }
                .padding(8)
            }
            if zoom > 1.05 {
                Text(String(format: "%.1f×  ·  double tap to fit", zoom))
                    .font(Theme.font(12, weight: .medium))
                    .foregroundStyle(Theme.gold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.65), in: Capsule())
                    .padding(.top, 8)
            }
            if let warn = warning {
                Text(warn.text)
                    .font(Theme.font(13, weight: .medium))
                    .foregroundStyle(warn.bad ? Theme.err : Theme.warn)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7), in: Capsule())
                    .padding(.top, 10)
            }
        }
        .clipped()
    }

    private var main: some View {
        VStack(spacing: 10) {
            frame()
            HStack(spacing: 8) {
                ForEach(dims, id: \.1) { dim in
                    Button { model.go(dim.0) } label: { tile(dim.1, dim.2, text(dim.1), compact: false) }
                }
            }
            .frame(height: 92)
        }
    }

    private var playButton: some View {
        Button { model.go(.playback) } label: {
            ZStack {
                Theme.s1
                if let shot = model.shots.first {
                    PairPicture(shot: shot, rig: model.rig, squeeze: model.photo.frame.squeeze)
                } else {
                    Image(systemName: "play.fill").foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hair, lineWidth: 1))
        }
        .accessibilityLabel("Playback")
    }

    private var shutterButton: some View {
        Button { Task { await model.fire() } } label: {
            ZStack {
                Circle().stroke(model.shooting ? Theme.red : Theme.hair2, lineWidth: 2)
                Circle()
                    .fill(online ? Theme.red : Color(hex: 0x5A2020))
                    .padding(6)
                    .scaleEffect(model.shooting ? 0.92 : 1)
                if model.photo.drive.timer > 0 && !model.shooting {
                    Text("\(model.photo.drive.timer)s")
                        .font(Theme.font(11, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 76, height: 76)
        }
        .accessibilityLabel("Release")
        .disabled(!online && !model.simulate)
    }

    private var liveButton: some View {
        Button { Task { await model.toggleLive() } } label: {
            VStack(spacing: 4) {
                Image(systemName: model.camera.live ? "eye" : "eye.slash")
                Text(model.camera.live ? "Live" : "Live off")
                    .font(Theme.font(11, weight: .medium))
            }
            .foregroundStyle(model.camera.live ? Theme.gold : Theme.dim)
            .frame(width: 72, height: 44)
        }
    }

    private var railVertical: some View {
        VStack(spacing: 12) {
            playButton
            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)
            liveButton
        }
    }

    private var railHorizontal: some View {
        HStack(spacing: 18) {
            playButton
            Spacer(minLength: 0)
            shutterButton
            Spacer(minLength: 0)
            liveButton
        }
        .frame(height: 84)
    }

    private var online: Bool {
        model.camera.slots.values.contains { $0.online }
    }

    private var warning: (text: String, bad: Bool)? {
        if model.simulate { return nil }
        let t = model.camera.slots[.t]
        let r = model.camera.slots[.r]
        let out = [t, r].filter { ($0?.paired ?? false) && !($0?.online ?? false) }
        if (t?.paired ?? false) && (r?.paired ?? false) && out.count == 2 {
            return ("No bodies on USB", true)
        }
        if out.count == 1 {
            let who = (t?.online ?? false) ? "R" : "T"
            return ("\(who) off USB", true)
        }
        if let t, let r, t.online, r.online, !model.photo.light.followCam {
            if norm(t.iso) != norm(r.iso) || norm(t.shutter) != norm(r.shutter) {
                return ("Bodies differ · ISO T \(t.iso) R \(r.iso)", false)
            }
        }
        return nil
    }

    private func norm(_ s: String) -> String {
        s.replacingOccurrences(of: "iso", with: "", options: .caseInsensitive).filter { !$0.isWhitespace }.lowercased()
    }

    private func tile(_ title: String, _ icon: String, _ lines: (String, String), compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: compact ? 2 : 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: compact ? 10 : 12))
                Text(title.uppercased())
                    .font(Theme.font(compact ? 10 : 11, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(Theme.dim)
            Spacer(minLength: 0)
            Text(lines.0)
                .font(Theme.font(compact ? 15 : 18, weight: .medium))
                .lineLimit(1)
            Text(lines.1)
                .font(Theme.font(compact ? 11 : 12))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(compact ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hair, lineWidth: 1))
    }

    private func text(_ title: String) -> (String, String) {
        let photo = model.photo
        switch title {
        case "Frame":
            let f = Catalog.format(photo.frame.squeeze)
            let g = Catalog.guide(photo.frame.guide)
            let sub = f.0 == 1 ? "Native · 65 MP" : f.2.replacingOccurrences(of: "Anamorphic", with: "Ana") + " · " + f.3
            return (f.1, sub + (g.1 > 0 ? " · \(g.2) guide" : ""))
        case "Light":
            return (Catalog.fmtISO(photo.light.iso), "\(Catalog.fmtShut(photo.light.shutter)) · \(Catalog.fmtF(photo.light.fstop)) · \(photo.light.program)")
        case "Focus":
            if photo.focus.aid == "off" { return ("Off", "Lens helicoid") }
            if photo.focus.aid == "range" {
                return ("Range", model.focusAt == nil ? "Box on the sharp part" : "Watching your point")
            }
            let aid = photo.focus.aid.prefix(1).uppercased() + photo.focus.aid.dropFirst()
            return (String(aid), "\(photo.focus.color) · \(photo.focus.level)")
        case "Look":
            let bits = LookBook.tweaks(photo.look)
            return (LookBook.name(photo.look), bits.isEmpty ? LookBook.note(photo.look) : bits.joined(separator: " · "))
        case "Drive":
            let engine = Catalog.engines.first { $0.0 == photo.drive.engine }?.1 ?? photo.drive.engine
            let save = photo.drive.save == "cards" ? "Cards" : (photo.drive.save == "both" ? "Both" : (UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad"))
            let release = photo.drive.release == "sync" ? "Sync" : "USB"
            return (release, [save, photo.drive.autoStitch ? engine : "Hold stitch"].joined(separator: " · "))
        default:
            let w = Catalog.wbRow(photo.wb)
            return (w.1, w.2 > 0 ? "\(w.2) K" : "Bodies decide")
        }
    }
}
