import Network
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let _ = model.cameraRevision
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                TopBar()
                if let stitch = model.stitchLabel {
                    HStack(spacing: 10) {
                        Text(stitch)
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(Theme.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Cancel") { model.cancelStitch() }
                            .font(Theme.font(13, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.s3, in: Capsule())
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 4)
                }
                ZStack {
                    HomeView().opacity(model.route.isEmpty ? 1 : 0)
                    if let route = model.route.last {
                        screen(route)
                            .background(Theme.bg)
                            .transition(.move(edge: .trailing))
                    }
                }
            }
            if let n = model.countdown {
                Text("\(n)")
                    .font(Theme.font(120, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .shadow(color: .black.opacity(0.6), radius: 12)
            }
            if let toast = model.toast {
                VStack {
                    Spacer()
                    Text(toast.text)
                        .font(Theme.font(14, weight: .medium))
                        .foregroundStyle(toast.bad ? Theme.err : Theme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Theme.s2, in: Capsule())
                        .overlay(Capsule().stroke(toast.bad ? Theme.err : Theme.hair2, lineWidth: 1))
                        .padding(.bottom, 24)
                }
            }
            if let stamp = model.reviewStamp, let shot = model.shots.first(where: { $0.stamp == stamp }) {
                ReviewOverlay(shot: shot)
            }
            if let url = model.peepURL {
                PeepScreen(url: url, title: model.peepTitle) { model.closePeep() }
            }
            if model.sleeping {
                ZStack {
                    Theme.bg.opacity(0.94).ignoresSafeArea()
                    VStack(spacing: 8) {
                        Text("Sleeping")
                            .font(Theme.font(22, weight: .medium))
                        Text("Touch to wake")
                            .font(Theme.font(14))
                            .foregroundStyle(Theme.dim)
                    }
                }
                .onTapGesture { model.poke() }
            }
        }
        .foregroundStyle(Theme.ink)
        .font(Theme.font(15))
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in model.poke() }
        )
    }

    @ViewBuilder
    private func screen(_ route: Route) -> some View {
        switch route {
        case .home: HomeView()
        case .frame: FrameScreen()
        case .light: LightScreen()
        case .focus: FocusScreen()
        case .look: LookScreen()
        case .drive: DriveScreen()
        case .wb: WBScreen()
        case .modes: ModesScreen()
        case .playback: PlaybackScreen()
        case .shot(let stamp): ShotScreen(stamp: stamp)
        case .system: SystemScreen()
        case .cameras: CamerasScreen()
        case .rig: RigScreen()
        case .display: DisplayScreen()
        case .storage: StorageScreen()
        case .about: AboutScreen()
        }
    }
}

@MainActor
@Observable
final class PadStatus {
    var level: Float = -1
    var charging = false
    var wifi = false
    private var monitor: NWPathMonitor?

    private var observers: [NSObjectProtocol] = []

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        refreshBattery()
        let center = NotificationCenter.default
        for name in [UIDevice.batteryLevelDidChangeNotification, UIDevice.batteryStateDidChangeNotification, UIApplication.didBecomeActiveNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshBattery() }
            })
        }
        let monitor = NWPathMonitor(requiredInterfaceType: .wifi)
        monitor.pathUpdateHandler = { path in
            let on = path.status == .satisfied
            Task { @MainActor in self.wifi = on }
        }
        monitor.start(queue: DispatchQueue(label: "fxpan.pad"))
        self.monitor = monitor
        Task { @MainActor in self.refreshBattery() }
    }

    func refreshBattery() {
        let device = UIDevice.current
        level = device.batteryLevel
        charging = device.batteryState == .charging || device.batteryState == .full
    }
}

struct TopBar: View {
    @Environment(AppModel.self) private var model
    @State private var pad = PadStatus()

    var body: some View {
        let _ = model.cameraRevision
        GeometryReader { geo in
            bar(compact: geo.size.width < 560)
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 46)
        .background(Theme.bg)
    }

    private func bar(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            Button { model.home() } label: {
                Image("FXPANWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(height: compact ? 22 : 34)
                    .accessibilityLabel("FXPAN")
            }
            Button { model.go(.modes) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person")
                    if !compact {
                        Text(model.activeMode?.name ?? "Modes")
                    }
                    if model.modeDrifted {
                        Circle().fill(Theme.gold).frame(width: 6, height: 6)
                    }
                    if !compact {
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                    }
                }
                .font(Theme.font(14, weight: .medium))
                .padding(.horizontal, compact ? 8 : 10)
                .padding(.vertical, 6)
                .background(Theme.s2, in: Capsule())
            }
            HStack(spacing: 6) {
                pill(.r, compact: compact)
                pill(.t, compact: compact)
            }
            Spacer(minLength: 0)
            if model.photo.drive.release == "sync" {
                HStack(spacing: 5) {
                    Circle()
                        .fill(model.syncReady ? Theme.gold : Theme.faint)
                        .frame(width: 7, height: 7)
                    if !compact {
                        Text("Sync")
                            .font(Theme.font(13, weight: .medium))
                            .foregroundStyle(model.syncReady ? Theme.ink : Theme.dim)
                    }
                }
                .accessibilityLabel(model.syncReady ? "Sync board answering" : "Sync board not answering")
            }
            if let stitch = model.stitchLabel {
                Button { model.go(.playback) } label: {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).tint(Theme.gold)
                        if !compact {
                            Text(stitch).font(Theme.font(13))
                        }
                    }
                }
            }
            Button { model.go(.storage) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sdcard")
                    if !compact {
                        Text(sets)
                    }
                }
                .font(Theme.font(13))
                .foregroundStyle(Theme.dim)
            }
            Image(systemName: pad.wifi ? "wifi" : "wifi.slash")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(pad.wifi ? Theme.ink : Theme.faint)
                .accessibilityLabel(pad.wifi ? "Wi-Fi connected" : "Wi-Fi off")
            PadBattery(level: pad.level, charging: pad.charging)
                .onReceive(Timer.publish(every: 15, on: .main, in: .common).autoconnect()) { _ in
                    pad.refreshBattery()
                }
            if model.simulate && !compact {
                Button { model.go(.system) } label: {
                    Text("SIM")
                        .font(Theme.font(11, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Theme.goldInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.gold, in: Capsule())
                }
            }
            Button { model.go(.system) } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .foregroundStyle(Theme.ink2)
            }
        }
        .padding(.horizontal, compact ? 10 : 14)
    }

    private var sets: String {
        guard let n = model.setsLeft() else { return "—" }
        if n >= 10_000 { return "\(n / 1000)k" }
        return n.formatted()
    }

    private func pill(_ role: Role, compact: Bool) -> some View {
        let slot = model.camera.slots[role] ?? BodyState()
        let tint = role == .t ? Theme.transmit : Theme.reflect
        let pct = slot.battery
        return Button { model.go(.cameras) } label: {
            HStack(spacing: 6) {
                Text(role.rawValue).font(Theme.font(12, weight: .semibold)).foregroundStyle(tint)
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.s3)
                    Capsule().fill(slot.online && (pct ?? 100) <= 20 ? Theme.err : tint)
                        .frame(width: slot.online ? CGFloat(pct ?? 0) / 100 * (compact ? 18 : 28) : 0)
                }
                .frame(width: compact ? 18 : 28, height: 6)
                if !compact {
                    Text(!slot.online ? "out" : (pct.map { "\($0)%" } ?? "USB"))
                        .font(Theme.font(11))
                        .foregroundStyle(slot.online ? Theme.ink2 : Theme.faint)
                        .frame(width: 36, alignment: .leading)
                }
            }
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 5)
            .background(Theme.s1, in: Capsule())
            .overlay(Capsule().stroke(Theme.hair, lineWidth: 1))
            .opacity(slot.online ? 1 : 0.55)
        }
    }
}

struct PadBattery: View {
    var level: Float
    var charging: Bool
    var showsPercent = true

    var body: some View {
        let known = level >= 0
        let fraction = known ? CGFloat(min(1, max(0, level))) : 0
        let low = known && fraction <= 0.2 && !charging
        let ink = low ? Theme.err : Theme.ink
        HStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 2.5)
                    .stroke(ink, lineWidth: 1)
                    .frame(width: 24, height: 12)
                RoundedRectangle(cornerRadius: 1)
                    .fill(ink)
                    .frame(width: max(2, 20 * fraction), height: 8)
                    .frame(width: 20, height: 8, alignment: .leading)
                Capsule()
                    .fill(ink)
                    .frame(width: 1.6, height: 4)
                    .offset(x: 14)
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(Theme.gold)
                        .shadow(color: .black.opacity(0.9), radius: 0.4)
                        .offset(x: -1)
                }
            }
            .frame(width: 30, height: 14)
            if showsPercent {
                Text(known ? "\(Int((fraction * 100).rounded()))%" : "—")
                    .font(Theme.font(12))
                    .foregroundStyle(low ? Theme.err : Theme.dim)
            }
        }
        .accessibilityLabel(charging ? "Charging, \(known ? "\(Int((fraction * 100).rounded())) percent" : "battery")" : "Battery")
    }
}

struct DimPage<Controls: View, Panel: View>: View {
    @Environment(AppModel.self) private var model
    var title: String
    var crumb: String?
    @ViewBuilder var controls: () -> Controls
    @ViewBuilder var panel: () -> Panel

    var body: some View {
        let usb = model.usbRevision
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.back() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 36, height: 36)
                }
                VStack(alignment: .leading, spacing: 0) {
                    if let crumb {
                        Text(crumb.uppercased())
                            .font(Theme.font(10, weight: .semibold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.faint)
                    }
                    Text(title).font(Theme.font(22, weight: .medium))
                }
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    ScrollView { controls().padding(.bottom, 20) }
                        .frame(maxWidth: 460)
                    panel()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        panel().frame(minHeight: 180)
                        controls()
                    }
                    .padding(.bottom, 24)
                }
            }
            .padding(.horizontal, 12)
        }
        .id(usb)
    }
}

struct ChipRow: View {
    var options: [(String, String)]
    var selected: String
    var onSelect: (String) -> Void

    var body: some View {
        Flow(spacing: 8) {
            ForEach(options, id: \.0) { option in
                let on = option.0 == selected
                PressChip(title: option.1, on: on) { onSelect(option.0) }
            }
        }
    }
}

struct Ruler: View {
    var values: [String]
    var selected: String
    var label: (String) -> String
    var onSelect: (String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        let on = value == selected
                        Text(label(value))
                            .font(Theme.font(on ? 18 : 14, weight: on ? .medium : .regular))
                            .foregroundStyle(on ? Theme.gold : Theme.dim)
                            .frame(minWidth: 72, minHeight: 44)
                            .contentShape(Rectangle())
                            .highPriorityGesture(TapGesture().onEnded { onSelect(value) })
                            .id(value)
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radiusS))
            .onAppear { proxy.scrollTo(selected, anchor: .center) }
            .onChange(of: selected) { _, value in
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
            }
        }
    }
}

struct RowBlock<Content: View>: View {
    var title: String
    var value: String
    var hint: String = ""
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(Theme.font(11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(Theme.dim)
                Spacer()
                Text(value).font(Theme.font(14)).foregroundStyle(Theme.ink2)
            }
            if !hint.isEmpty {
                Text(hint).font(Theme.font(12)).foregroundStyle(Theme.faint)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.s1, in: RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.hair, lineWidth: 1))
    }
}

struct Flow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += row + spacing
                row = 0
            }
            row = max(row, size.height)
            x += size.width + spacing
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += row + spacing
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            row = max(row, size.height)
            x += size.width + spacing
        }
    }
}

struct PanoFrame: View {
    @Environment(AppModel.self) private var model
    var showGuide = true
    var showLiveHint = false

    var body: some View {
        let squeeze = model.photo.frame.squeeze
        let aspect = Catalog.nativeAspect * max(squeeze, 1)
        ZStack {
            Color.black
            if let preview = model.preview {
                Image(uiImage: preview)
                    .resizable()
                    .scaledToFit()
                    .padding(.bottom, 36)
            } else {
                VStack(spacing: 8) {
                    Text("No frame yet")
                        .font(Theme.font(16, weight: .medium))
                    if showLiveHint {
                        Text("Tap to start live view")
                            .font(Theme.font(13))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            if showGuide, let ratio = guideRatio {
                GuideLines(ratio: ratio, frame: aspect)
            }
            if model.photo.focus.aid == "loupe", model.preview != nil {
                Loupe()
            }
            VStack {
                Spacer()
                exposureStrip
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private var guideRatio: Double? {
        let g = Catalog.guide(model.photo.frame.guide)
        return g.1 > 0 ? g.1 : nil
    }

    private var exposureStrip: some View {
        let light = model.photo.light
        let format = Catalog.format(model.photo.frame.squeeze)
        return HStack(spacing: 0) {
            cell(light.followCam ? "Camera decides" : light.program, gold: !light.followCam)
            if !light.followCam {
                cell(Catalog.fmtISO(light.iso))
                cell(Catalog.fmtShut(light.bulb ? light.shutter : light.shutter) + (light.bulb ? " bulb" : ""))
                cell(Catalog.fmtF(light.fstop))
            }
            cell(format.1, dim: true)
        }
        .background(.black.opacity(0.55))
    }

    private func cell(_ text: String, gold: Bool = false, dim: Bool = false) -> some View {
        Text(text)
            .font(Theme.font(13, weight: gold ? .semibold : .regular))
            .foregroundStyle(gold ? Theme.gold : (dim ? Theme.dim : Theme.ink))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

struct GuideLines: View {
    var ratio: Double
    var frame: Double

    var body: some View {
        GeometryReader { geo in
            let inset = max(0, (geo.size.width - geo.size.height * ratio) / 2)
            Path { path in
                if ratio < frame {
                    path.move(to: CGPoint(x: inset, y: 8))
                    path.addLine(to: CGPoint(x: inset, y: geo.size.height - 44))
                    path.move(to: CGPoint(x: geo.size.width - inset, y: 8))
                    path.addLine(to: CGPoint(x: geo.size.width - inset, y: geo.size.height - 44))
                }
            }
            .stroke(Theme.gold.opacity(0.8), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct Loupe: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        if let preview = model.preview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 280, height: 160)
                .scaleEffect(2.2)
                .frame(width: 140, height: 80)
                .clipped()
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gold, lineWidth: 1))
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }
}

struct PairPicture: View {
    var shot: ShotFiles
    var rig: Rig
    var squeeze: Double
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: token) {
            let shot = shot
            let rig = rig
            let squeeze = squeeze
            image = await Task.detached(priority: .userInitiated) {
                Self.make(shot, rig: rig, squeeze: squeeze)
            }.value
        }
    }

    private var token: String {
        func revised(_ url: URL?) -> String {
            guard let url else { return "" }
            let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            return "\(url.path)#\(modified)"
        }
        return [shot.ana, shot.pano, shot.t, shot.r].map(revised).joined(separator: "|")
    }

    /// The finished panorama when it exists. Until then, T and R side by side the same way live view is composed.
    private static func make(_ shot: ShotFiles, rig: Rig, squeeze: Double) -> UIImage? {
        if let url = shot.ana ?? shot.pano, let cg = Stitcher.thumbnail(at: url, maxPixel: 1800) {
            return UIImage(cgImage: cg)
        }
        let t = shot.t.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1400) }
        let r = shot.r.flatMap { Stitcher.thumbnail(at: $0, maxPixel: 1400) }
        if let t, let r, let cg = Stitcher.preview(t: t, r: r, rig: rig, squeeze: squeeze, maxWidth: 1600) {
            return UIImage(cgImage: cg)
        }
        if let cg = t ?? r { return UIImage(cgImage: cg) }
        return nil
    }
}

struct ReviewOverlay: View {
    @Environment(AppModel.self) private var model
    var shot: ShotFiles

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                PairPicture(shot: shot, rig: model.rig, squeeze: model.photo.frame.squeeze)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .frame(maxHeight: 420)
                    .clipped()
                    .onLongPressGesture(minimumDuration: 0.35) {
                        model.peep(shot.ana ?? shot.pano ?? shot.t ?? shot.r, title: shot.name)
                    }
                HStack(spacing: 12) {
                    PressChip(title: "Keep", on: true) { model.reviewStamp = nil }
                    PressChip(title: "Delete", filled: false) { model.deleteShot(shot.stamp) }
                    PressChip(title: "Playback", filled: false) {
                        model.reviewStamp = nil
                        model.go(.shot(shot.stamp))
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
    }
}

struct GoldButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, weight: .semibold))
            .foregroundStyle(Theme.goldInk)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Theme.gold, in: Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct PeepScreen: View {
    var url: URL
    var title: String
    var close: () -> Void
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                ZoomImage(image: image)
                    .ignoresSafeArea()
            } else {
                ProgressView().tint(Theme.gold)
            }
            VStack {
                HStack {
                    Text(title)
                        .font(Theme.font(15, weight: .medium))
                        .foregroundStyle(Theme.gold)
                        .lineLimit(1)
                    Spacer()
                    Button("Close", action: close)
                        .buttonStyle(PlainChip())
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(.black.opacity(0.45))
                Spacer()
                Text("Pinch to inspect. Double tap for pixels.")
                    .font(Theme.font(12))
                    .foregroundStyle(Theme.dim)
                    .padding(.bottom, 12)
            }
        }
        .task(id: url) {
            let url = url
            let cg = await Task.detached(priority: .userInitiated) { Stitcher.image(at: url) }.value
            if let cg { image = UIImage(cgImage: cg) }
        }
    }
}

struct ZoomImage: UIViewRepresentable {
    var image: UIImage

    func makeUIView(context: Context) -> PeepScroll {
        let scroll = PeepScroll()
        scroll.photo.image = image
        return scroll
    }

    func updateUIView(_ scroll: PeepScroll, context: Context) {
        if scroll.photo.image !== image {
            scroll.photo.image = image
            scroll.fitted = false
        }
        scroll.fitIfNeeded()
    }
}

final class PeepScroll: UIScrollView, UIScrollViewDelegate {
    let photo = UIImageView()
    var fitted = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        delegate = self
        backgroundColor = .black
        bouncesZoom = true
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        contentInsetAdjustmentBehavior = .never
        photo.isUserInteractionEnabled = true
        addSubview(photo)
        let tap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        tap.numberOfTapsRequired = 2
        addGestureRecognizer(tap)
    }

    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        fitIfNeeded()
    }

    func fitIfNeeded() {
        guard let image = photo.image, !fitted, bounds.width > 1, bounds.height > 1 else { return }
        fitted = true
        photo.frame = CGRect(origin: .zero, size: image.size)
        contentSize = image.size
        let fit = min(bounds.width / image.size.width, bounds.height / image.size.height)
        minimumZoomScale = fit
        maximumZoomScale = max(1, fit * 8)
        zoomScale = fit
        centerPhoto()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { photo }

    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerPhoto() }

    private func centerPhoto() {
        let spareX = max(0, bounds.width - photo.frame.width)
        let spareY = max(0, bounds.height - photo.frame.height)
        photo.center = CGPoint(x: photo.frame.width / 2 + spareX / 2, y: photo.frame.height / 2 + spareY / 2)
    }

    @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.05 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: photo)
            let scale = min(maximumZoomScale, max(1, minimumZoomScale * 4))
            let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
            zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height), animated: true)
        }
    }
}

/// A chip that takes the tap inside a scrolling page. A normal button there waits to see if the finger is scrolling, and the press is dropped.
struct PressChip: View {
    var title: String
    var on = false
    /// Gold fill when selected. Role chips stay an outline so T and R keep their own colors in the list.
    var filled = true
    var action: () -> Void

    var body: some View {
        Text(title)
            .font(Theme.font(15, weight: on ? .semibold : .medium))
            .foregroundStyle(filled && on ? Theme.goldInk : (on ? Theme.gold : Theme.ink))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(filled && on ? Theme.gold : Theme.s2, in: Capsule())
            .overlay(Capsule().stroke(on ? Theme.gold : Theme.hair2, lineWidth: 1))
            .contentShape(Capsule())
            .highPriorityGesture(TapGesture().onEnded { action() })
    }
}

struct PlainChip: ButtonStyle {
    var on = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(15, weight: .medium))
            .foregroundStyle(on ? Theme.gold : Theme.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.s2, in: Capsule())
            .overlay(Capsule().stroke(on ? Theme.gold : Theme.hair2, lineWidth: 1))
    }
}
