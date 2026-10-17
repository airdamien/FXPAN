@preconcurrency import AVFoundation
import Darwin
import SwiftUI

/// Where the hotshoe phone's camera sits relative to the EL-Nikkor axis.
/// Degrees. Positive `down` looks below the lens. Positive `right` is the photographer's right.
/// These are a working-distance guess. A measured alignment replaces them.
struct ShoeAim: Equatable {
    var down: Double
    var right: Double
    /// Rear island on a slab phone or a Duo held flat. The camera outside the Duo's fold.
    var outer: Bool

    /// 17 Pro Max, landscape, screen toward the photographer. The rear island is the upper-left of the cradle,
    /// so those cameras sit left of and above the lens. The cradle also leans the screen back 30°.
    /// That lean is not applied here: it would walk the 100 mm telephoto off the panorama, and the
    /// stand-in would become a soft slice of the ultrawide. The lean gets folded in once it is measured.
    static let proMax = ShoeAim(down: 2.2, right: 1.6, outer: false)

    /// The camera on the outside of the Duo, not the one inside the fold. A few degrees down is a guess
    /// for where that camera sits above the lens. Used on the cover and while the hinge is only partly open.
    static let duo = ShoeAim(down: 4.0, right: 0, outer: true)

    /// Fully open and landscape, on the flat mount. The rear island faces the lens.
    /// The offset stays at zero until that mount is measured.
    static let duoFlat = ShoeAim(down: 0, right: 0, outer: false)
}

enum ShoePhone {
    case proMax
    case duo

    static var current: ShoePhone {
        if !ShoeFinder.outerCameras().isEmpty { return .duo }
        let id = machine()
        if id.localizedCaseInsensitiveContains("fold") || id == "iPhone19,4" { return .duo }
        if ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4" { return .duo }
        return .proMax
    }

    /// Cover and half-open keep the outer camera. Full landscape uses the rear island.
    func aim(flat: Bool) -> ShoeAim {
        switch self {
        case .proMax: return .proMax
        case .duo: return flat ? .duoFlat : .duo
        }
    }

    private static func machine() -> String {
        var system = utsname()
        uname(&system)
        return withUnsafePointer(to: &system.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

enum ShoeFrame {
    /// The stitched gate at 180 mm. FXPAN is 64.80 × 23.9 mm. DXPAN is 42.48 × 15.6 mm.
    static func gate(kind: BodyKind) -> (h: Double, v: Double) {
        let width: Double = kind == .d7000 ? 42.48 : 64.80
        let height: Double = kind == .d7000 ? 15.6 : 23.9
        let focal = 180.0
        return (degrees(2 * atan((width / 2) / focal)), degrees(2 * atan((height / 2) / focal)))
    }

    /// Normalized crop of the upright camera image, origin at the top left.
    /// The window is shifted so the lens axis sits in the middle, then kept inside the sensor.
    static func window(sensorH: Double, sensorV: Double, rotation: CGFloat, wantH: Double, wantV: Double, aim: ShoeAim) -> CGRect {
        let quarter = Int((rotation / 90).rounded()) % 4
        let swap = quarter == 1 || quarter == 3 || quarter == -1 || quarter == -3
        let hFov = max(1, swap ? sensorV : sensorH)
        let vFov = max(1, swap ? sensorH : sensorV)
        var w = tan(radians(wantH / 2)) / tan(radians(hFov / 2))
        var h = tan(radians(wantV / 2)) / tan(radians(vFov / 2))
        w = min(1, max(0.05, w))
        h = min(1, max(0.05, h))
        let cx = 0.5 + tan(radians(aim.right)) / (2 * tan(radians(hFov / 2)))
        let cy = 0.5 + tan(radians(aim.down)) / (2 * tan(radians(vFov / 2)))
        var rect = CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
        if rect.minX < 0 { rect.origin.x = 0 }
        if rect.minY < 0 { rect.origin.y = 0 }
        if rect.maxX > 1 { rect.origin.x = 1 - rect.width }
        if rect.maxY > 1 { rect.origin.y = 1 - rect.height }
        return rect
    }

    fileprivate static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    fileprivate static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}

/// The phone camera, cropped to the 180 mm panorama, while the Nikons stay out of live view.
@MainActor
@Observable
final class ShoeFinder {
    private(set) var running = false
    private(set) var refused = false
    private(set) var lens = ""
    private(set) var sensorH: Double = 0
    private(set) var sensorV: Double = 0
    private(set) var pixelW: CGFloat = 0
    private(set) var pixelH: CGFloat = 0
    private(set) var wantH: Double = 20
    private(set) var wantV: Double = 8
    private(set) var aim = ShoeAim.proMax
    let session = AVCaptureSession()
    private(set) var device: AVCaptureDevice?

    private let queue = DispatchQueue(label: "fxpan.shoe")
    private var generation = 0
    private var kind = BodyKind.d800
    private var wanted = false
    private var flat = false
    private var observers: [NSObjectProtocol] = []

    init() {
        session.automaticallyConfiguresApplicationAudioSession = false
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        })
    }

    func start(kind: BodyKind) {
        let gate = ShoeFrame.gate(kind: kind)
        wantH = gate.h
        wantV = gate.v
        let next = ShoePhone.current.aim(flat: flat)
        if running, self.kind == kind, aim == next { return }
        aim = next
        if refused { return }
        self.kind = kind
        wanted = true
        generation += 1
        let gen = generation
        let aim = aim
        Task { [weak self] in
            let ok = await Self.authorize()
            guard let self, gen == self.generation, self.wanted else { return }
            guard ok else {
                self.refused = true
                self.stop()
                return
            }
            let session = self.session
            let wantH = self.wantH
            let wantV = self.wantV
            self.queue.async { [weak self] in
                let picked = Self.open(session, aim: aim, wantH: wantH, wantV: wantV)
                DispatchQueue.main.async { [weak self] in
                    guard let self, gen == self.generation, self.wanted else {
                        if session.isRunning {
                            self?.queue.async { if session.isRunning { session.stopRunning() } }
                        }
                        return
                    }
                    guard let picked, session.isRunning else {
                        self.lens = ""
                        self.running = false
                        Trace.line("FXPAN shoe no camera")
                        return
                    }
                    self.device = picked.device
                    self.sensorH = picked.hFov
                    self.sensorV = picked.vFov
                    self.pixelW = picked.pixelW
                    self.pixelH = picked.pixelH
                    self.lens = picked.name
                    self.running = true
                    Trace.line(String(format: "FXPAN shoe %@ fov %.1f×%.1f gate %.1f×%.1f", picked.name, picked.hFov, picked.vFov, wantH, wantV))
                }
            }
        }
    }

    /// Settings may have granted the camera after a refusal. The next start tries again.
    func allowRetry() {
        refused = false
    }

    /// Fully open landscape uses the rear island. The cover and a half-open hinge keep the outer camera.
    func setFlat(_ on: Bool) {
        guard on != flat else { return }
        flat = on
        guard wanted else { return }
        start(kind: kind)
    }

    func stop() {
        wanted = false
        generation += 1
        running = false
        let session = session
        queue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    private func resume() {
        guard wanted else { return }
        let session = session
        queue.async { [weak self] in
            if !session.isRunning { session.startRunning() }
            let on = session.isRunning
            DispatchQueue.main.async { [weak self] in
                guard let self, self.wanted else { return }
                self.running = on
            }
        }
    }

    private nonisolated static func authorize() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { done in
                AVCaptureDevice.requestAccess(for: .video) { done.resume(returning: $0) }
            }
        default: return false
        }
    }

    private nonisolated static func open(_ session: AVCaptureSession, aim: ShoeAim, wantH: Double, wantV: Double) -> Pick? {
        guard let picked = pick(aim: aim, wantH: wantH, wantV: wantV) else { return nil }
        session.beginConfiguration()
        for input in session.inputs { session.removeInput(input) }
        do {
            let input = try AVCaptureDeviceInput(device: picked.device)
            if session.canAddInput(input) { session.addInput(input) }
        } catch {
            session.commitConfiguration()
            return nil
        }
        session.commitConfiguration()
        if !session.isRunning { session.startRunning() }
        return session.isRunning ? picked : nil
    }

    private struct Pick {
        var device: AVCaptureDevice
        var hFov: Double
        var vFov: Double
        var pixelW: CGFloat
        var pixelH: CGFloat
        var name: String
    }

    private nonisolated static func pick(aim: ShoeAim, wantH: Double, wantV: Double) -> Pick? {
        let devices = aim.outer ? outerCameras() : rearCameras()
        var best: (pick: Pick, area: Double)?
        for device in devices {
            guard let format = format(device) else { continue }
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                let ranges = device.activeFormat.videoSupportedFrameRateRanges
                if ranges.contains(where: { $0.minFrameRate <= 30 && $0.maxFrameRate >= 30 }) {
                    let frame = CMTime(value: 1, timescale: 30)
                    device.activeVideoMaxFrameDuration = frame
                    device.activeVideoMinFrameDuration = frame
                }
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
                device.unlockForConfiguration()
            } catch {
                continue
            }
            let dims = CMVideoFormatDescriptionGetDimensions(device.activeFormat.formatDescription)
            let hFov = Double(device.activeFormat.videoFieldOfView)
            guard hFov > 1, dims.width > 0, dims.height > 0 else { continue }
            let vFov = ShoeFrame.degrees(2 * atan(tan(ShoeFrame.radians(hFov / 2)) * Double(dims.height) / Double(dims.width)))
            let spanH = tan(ShoeFrame.radians(wantH / 2)) / tan(ShoeFrame.radians(hFov / 2))
            let spanV = tan(ShoeFrame.radians(wantV / 2)) / tan(ShoeFrame.radians(vFov / 2))
            guard spanH > 0.05, spanV > 0.05, spanH < 1.8, spanV < 1.8 else { continue }
            let area = min(spanH, 1) * min(spanV, 1)
            let pick = Pick(device: device, hFov: hFov, vFov: vFov, pixelW: CGFloat(dims.width), pixelH: CGFloat(dims.height), name: shortName(device))
            if best == nil || area > best!.area { best = (pick, area) }
        }
        return best?.pick
    }

    /// The rear island: telephoto, main, and ultrawide. The front camera is not in this list.
    private nonisolated static func rearCameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTelephotoCamera, .builtInWideAngleCamera, .builtInUltraWideCamera],
            mediaType: .video,
            position: .back
        ).devices.filter { $0.position == .back }
    }

    /// The camera outside the fold. The inner one is left out on purpose.
    nonisolated static func outerCameras() -> [AVCaptureDevice] {
        guard #available(iOS 27.1, *) else { return [] }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInOuterUltraWideCamera],
            mediaType: .video,
            position: .unspecified
        ).devices.filter { $0.deviceType == .builtInOuterUltraWideCamera }
    }

    /// The widest field, at the smallest size that still shows it. A center-cropped format would miss the panorama.
    private nonisolated static func format(_ device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        let pool = device.formats.filter { $0.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 } }
        guard let widest = pool.map(\.videoFieldOfView).max() else { return device.formats.first }
        let wide = pool.filter { abs($0.videoFieldOfView - widest) < 0.6 }
        return wide.min { a, b in
            let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
            let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
            let pa = Int(da.width) * Int(da.height)
            let pb = Int(db.width) * Int(db.height)
            return pa < pb
        }
    }

    private nonisolated static func shortName(_ device: AVCaptureDevice) -> String {
        switch device.deviceType {
        case .builtInTelephotoCamera: return "Tele"
        case .builtInUltraWideCamera: return "Ultra"
        case .builtInWideAngleCamera: return "Main"
        default:
            if #available(iOS 27.1, *), device.deviceType == .builtInOuterUltraWideCamera { return "Outer" }
            return "Rear"
        }
    }
}

struct ShoePreview: UIViewRepresentable {
    var session: AVCaptureSession
    var device: AVCaptureDevice?
    var sensorH: Double
    var sensorV: Double
    var pixelW: CGFloat
    var pixelH: CGFloat
    var wantH: Double
    var wantV: Double
    var aim: ShoeAim

    func makeUIView(context: Context) -> ShoeHost {
        let host = ShoeHost()
        host.preview.session = session
        host.preview.videoGravity = .resizeAspect
        apply(host)
        return host
    }

    func updateUIView(_ host: ShoeHost, context: Context) {
        if host.preview.session !== session { host.preview.session = session }
        apply(host)
        host.setNeedsLayout()
    }

    private func apply(_ host: ShoeHost) {
        host.sensorH = sensorH
        host.sensorV = sensorV
        host.pixelW = pixelW
        host.pixelH = pixelH
        host.wantH = wantH
        host.wantV = wantV
        host.aim = aim
        host.attach(device)
    }

    final class ShoeHost: UIView {
        let preview = AVCaptureVideoPreviewLayer()
        var sensorH: Double = 0
        var sensorV: Double = 0
        var pixelW: CGFloat = 0
        var pixelH: CGFloat = 0
        var wantH: Double = 20
        var wantV: Double = 8
        var aim = ShoeAim.proMax
        private var coordinator: AVCaptureDevice.RotationCoordinator?
        private var attachedID = ""
        private var watch: NSKeyValueObservation?
        private var angle: CGFloat = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true
            preview.videoGravity = .resizeAspect
            preview.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            preview.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
            layer.addSublayer(preview)
            backgroundColor = .black
        }

        required init?(coder: NSCoder) { nil }

        func attach(_ device: AVCaptureDevice?) {
            guard let device else { return }
            if attachedID == device.uniqueID { return }
            attachedID = device.uniqueID
            let made = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
            coordinator = made
            watch = made.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] made, _ in
                let angle = made.videoRotationAngleForHorizonLevelPreview
                DispatchQueue.main.async {
                    guard let self, abs(self.angle - angle) > 0.5 else { return }
                    self.angle = angle
                    self.setNeedsLayout()
                }
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            guard bounds.width > 2, bounds.height > 2 else { return }
            if let coordinator {
                angle = coordinator.videoRotationAngleForHorizonLevelPreview
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            applyConnection()
            place()
            CATransaction.commit()
        }

        /// The full upright frame sits behind the panorama slot. The slot clips to the 180 mm gate.
        private func place() {
            guard sensorH > 1, sensorV > 1, pixelW > 2, pixelH > 2 else {
                preview.bounds = bounds
                preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
                return
            }
            let crop = ShoeFrame.window(sensorH: sensorH, sensorV: sensorV, rotation: angle, wantH: wantH, wantV: wantV, aim: aim)
            let quarter = Int((angle / 90).rounded()) % 4
            let swap = quarter == 1 || quarter == 3 || quarter == -1 || quarter == -3
            let uprightW = swap ? pixelH : pixelW
            let uprightH = swap ? pixelW : pixelH
            let cropW = max(1, crop.width * uprightW)
            let cropH = max(1, crop.height * uprightH)
            let scale = max(bounds.width / cropW, bounds.height / cropH)
            let video = CGSize(width: uprightW * scale, height: uprightH * scale)
            let cropOrigin = CGPoint(x: crop.minX * video.width, y: crop.minY * video.height)
            let cropSize = CGSize(width: crop.width * video.width, height: crop.height * video.height)
            let originX = (bounds.width - cropSize.width) / 2 - cropOrigin.x
            let originY = (bounds.height - cropSize.height) / 2 - cropOrigin.y
            preview.bounds = CGRect(origin: .zero, size: video)
            preview.position = CGPoint(x: originX + video.width / 2, y: originY + video.height / 2)
        }

        private func applyConnection() {
            guard let connection = preview.connection else { return }
            if connection.isVideoRotationAngleSupported(angle), abs(connection.videoRotationAngle - angle) > 0.5 {
                connection.videoRotationAngle = angle
            }
            if connection.isVideoMirroringSupported, connection.isVideoMirrored {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }
    }
}

/// R on the left and T on the right, in the same proportions as the stitch.
struct ShoeMarks: View {
    var overlap: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(0.1, 2 - overlap)
            let unit = geo.size.width / span
            let h = geo.size.height
            let rRect = CGRect(x: 0, y: 0, width: unit, height: h)
            let tRect = CGRect(x: unit * (1 - overlap), y: 0, width: unit, height: h)
            ZStack(alignment: .topLeading) {
                box(rRect, Theme.reflect)
                box(tRect, Theme.transmit)
                Text("R")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.reflect)
                    .position(x: 14, y: h / 2)
                Text("T")
                    .font(Theme.font(11, weight: .semibold))
                    .foregroundStyle(Theme.transmit)
                    .position(x: geo.size.width - 14, y: h / 2)
            }
        }
        .allowsHitTesting(false)
    }

    private func box(_ rect: CGRect, _ color: Color) -> some View {
        Path { $0.addRect(rect.insetBy(dx: 0.5, dy: 0.5)) }
            .stroke(color.opacity(0.9), lineWidth: 1)
    }
}
