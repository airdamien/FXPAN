import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

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
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width >= 980
            if wide {
                HStack(spacing: 10) {
                    main
                    railVertical
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

    private var main: some View {
        VStack(spacing: 10) {
            ZStack(alignment: .top) {
                Button { Task { await model.toggleLive() } } label: {
                    PanoFrame(showLiveHint: !model.camera.live)
                }
                .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                ForEach(dims, id: \.1) { dim in
                    Button { model.go(dim.0) } label: { tile(dim.1, dim.2, text(dim.1)) }
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
        .frame(width: 96)
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

    private func tile(_ title: String, _ icon: String, _ lines: (String, String)) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 12))
                Text(title.uppercased())
                    .font(Theme.font(11, weight: .semibold))
                    .tracking(1.2)
            }
            .foregroundStyle(Theme.dim)
            Spacer(minLength: 0)
            Text(lines.0)
                .font(Theme.font(18, weight: .medium))
                .lineLimit(1)
            Text(lines.1)
                .font(Theme.font(12))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
        }
        .padding(10)
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
            let aid = photo.focus.aid.prefix(1).uppercased() + photo.focus.aid.dropFirst()
            return (aid == "Off" ? "Off" : String(aid), photo.focus.aid == "off" ? "Lens helicoid" : "\(photo.focus.color) · \(photo.focus.level)")
        case "Look":
            let bits = LookBook.tweaks(photo.look)
            return (LookBook.name(photo.look), bits.isEmpty ? LookBook.note(photo.look) : bits.joined(separator: " · "))
        case "Drive":
            let engine = Catalog.engines.first { $0.0 == photo.drive.engine }?.1 ?? photo.drive.engine
            let save = photo.drive.save == "cards" ? "Cards" : (photo.drive.save == "both" ? "Both" : "iPad")
            return ("USB", [save, photo.drive.autoStitch ? engine : "Hold stitch"].joined(separator: " · "))
        default:
            let w = Catalog.wbRow(photo.wb)
            return (w.1, w.2 > 0 ? "\(w.2) K" : "Bodies decide")
        }
    }
}
