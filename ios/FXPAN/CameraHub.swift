import ImageCaptureCore
import UIKit

struct BodyState: Equatable {
    var online = false
    var paired = false
    var serial = ""
    var model = ""
    var battery: Int?
    var iso = ""
    var shutter = ""
    var fstop = ""
    var program = ""
    var wb = ""
}

struct DetectedCamera: Identifiable, Equatable {
    var id: String
    var token: String
    var serial: String
    var model: String
    var role: Role?
}

struct Grabbed {
    var jpeg: URL?
    var nef: URL?
}

/// USB PTP for the paired Nikons, plus a no-cable scene so the UI runs in the Simulator.
@MainActor
final class CameraHub: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    var onChange: (() -> Void)?

    var simulate = false {
        didSet { publish(); if simulate { installSim() } else { frames = realFrames } }
    }

    private(set) var slots: [Role: BodyState] = [.t: BodyState(), .r: BodyState()]
    private(set) var detected: [DetectedCamera] = []
    private(set) var frames: [Role: UIImage] = [:]
    private(set) var live = false
    private(set) var line = "No bodies on USB"
    var controlAuthorized = true

    private var pairT = ""
    private var pairR = ""
    private let browser = ICDeviceBrowser()
    private var links: [String: NikonLink] = [:]
    private var realFrames: [Role: UIImage] = [:]
    private var simPhase: CGFloat = 0
    private var simTimer: Timer?
    private var started = false
    private var livePoll: Task<Void, Never>?
    private var liveLine = "Live"

    func start() async {
        if started { return }
        started = true
        let pair = Disk.loadPair()
        pairT = Self.kept(pair.t)
        pairR = Self.kept(pair.r)
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        await authorize()
        browser.start()
        if simulate { installSim() }
        publish()
    }

    func pair(_ serial: String, role: Role) {
        guard !serial.isEmpty else { return }
        if role == .t {
            if pairR == serial { pairR = "" }
            pairT = serial
        } else {
            if pairT == serial { pairT = "" }
            pairR = serial
        }
        Disk.savePair(t: pairT, r: pairR)
        seat()
        publish()
    }

    func clear(_ role: Role) {
        if role == .t { pairT = "" } else { pairR = "" }
        Disk.savePair(t: pairT, r: pairR)
        seat()
        publish()
    }

    func swap() {
        Swift.swap(&pairT, &pairR)
        Disk.savePair(t: pairT, r: pairR)
        seat()
        publish()
    }

    func apply(_ photo: Photo) async {
        guard !simulate, photo.exposes else { return }
        await withTaskGroup(of: Void.self) { group in
            for link in links.values where role(of: link.token) != nil {
                group.addTask { try? await link.apply(photo) }
            }
        }
        await refreshStatus()
    }

    private var liveGate = false

    func setLive(_ on: Bool) async {
        if on == live || liveGate { return }
        if simulate {
            live = on
            if on { startSimClock() } else { simTimer?.invalidate(); simTimer = nil }
            publish()
            return
        }
        let bodies = links.values.sorted { sideRank($0) < sideRank($1) }
        if on {
            liveGate = true
            defer { liveGate = false }
            if bodies.isEmpty {
                line = "No bodies on USB"
                publish()
                return
            }
            var up: [String] = []
            var down: [String] = []
            for (index, link) in bodies.enumerated() {
                if index > 0 { try? await Task.sleep(nanoseconds: 700_000_000) }
                let name = role(of: link.token)?.rawValue ?? link.model
                if await link.enterLive() { up.append(name) } else { down.append(name) }
            }
            guard !up.isEmpty else {
                line = "Live view refused"
                publish()
                return
            }
            live = true
            liveLine = down.isEmpty ? "Live" : "Live · \(down.joined(separator: ", ")) refused"
            publish()
            livePoll = Task { [weak self] in
                guard let self else { return }
                while self.live, !Task.isCancelled {
                    let snapshot = self.links.values.filter(\.inLive).sorted { self.sideRank($0) < self.sideRank($1) }
                    if snapshot.isEmpty { break }
                    // Each body has its own session, so the two GetLiveView calls run together.
                    let got: [(NikonLink, UIImage?)] = await withTaskGroup(of: (NikonLink, UIImage?).self) { group in
                        for link in snapshot {
                            group.addTask { @MainActor in (link, await link.nextFrame()) }
                        }
                        var rows: [(NikonLink, UIImage?)] = []
                        for await row in group { rows.append(row) }
                        return rows
                    }
                    if !self.live || Task.isCancelled { break }
                    for (link, image) in got {
                        if let image {
                            self.deliver(link, image)
                        } else if self.frames.isEmpty, !link.liveNote.isEmpty {
                            self.liveLine = link.liveNote
                            self.publish()
                        }
                    }
                }
            }
        } else {
            live = false
            let poll = livePoll
            livePoll = nil
            for link in bodies { await link.stopLive() }
            await poll?.value
            publish()
        }
    }

    private func sideRank(_ link: NikonLink) -> String {
        role(of: link.token)?.rawValue ?? link.token
    }

    private func deliver(_ link: NikonLink, _ image: UIImage) {
        guard let who = side(for: link) else { return }
        realFrames[who] = image
        guard !simulate else { return }
        frames[who] = image
        onChange?()
    }

    /// Paired body uses its role. An unpaired body fills an empty side so both previews show.
    private func side(for link: NikonLink) -> Role? {
        if let who = role(of: link.token) { return who }
        let taken = Set(links.values.compactMap { role(of: $0.token) })
        let open = Role.allCases.filter { !taken.contains($0) }
        let loose = links.values.filter { role(of: $0.token) == nil }.sorted { $0.token < $1.token }
        for (body, role) in zip(loose, open) where body === link { return role }
        return nil
    }

    func capture(stamp: String, photo: Photo) async throws -> [Role: Grabbed] {
        if simulate {
            let was = live
            live = false
            simTimer?.invalidate()
            let pair = SimScene.pair(phase: simPhase)
            var out: [Role: Grabbed] = [:]
            for (role, image) in [(Role.t, pair.t), (Role.r, pair.r)] {
                let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).jpg")
                try Stitcher.jpeg(image, to: url)
                frames[role] = UIImage(cgImage: image)
                out[role] = Grabbed(jpeg: url, nef: nil)
            }
            if was { live = true; startSimClock() }
            publish()
            return out
        }
        await setLive(false)
        var out: [Role: Grabbed] = [:]
        var failures: [String] = []
        await withTaskGroup(of: Result<(Role, Grabbed), Error>.self) { group in
            for link in links.values {
                guard let who = role(of: link.token) else { continue }
                group.addTask {
                    do {
                        let got = try await link.shoot(stamp: stamp, role: who, photo: photo)
                        return .success((who, got))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let pair):
                    out[pair.0] = pair.1
                case .failure(let error): failures.append(error.localizedDescription)
                }
            }
        }
        if out.isEmpty {
            throw PTPError.message(failures.first ?? "No paired body on USB")
        }
        await refreshStatus()
        return out
    }

    // MARK: - Browser

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        Task { @MainActor in self.adopt(device) }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        let key = device.uuidString ?? ""
        Task { @MainActor in
            if let link = self.links.removeValue(forKey: key) {
                await link.stopLive()
            }
            self.seat()
            self.publish()
        }
    }

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {}
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    nonisolated func didRemove(_ device: ICDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        let files = items.compactMap { $0 as? ICCameraFile }
        Task { @MainActor in self.arrivals.add(camera, files) }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {}

    // MARK: - Private

    private func authorize() async {
        // The Simulator's ImageCaptureCore advertises this and then throws
        // if you send it. A real iPad answers the prompt.
        let ask = Selector(("requestControlAuthorizationWithCompletion:"))
        guard browser.responds(to: ask) else {
            controlAuthorized = true
            return
        }
        let status = browser.controlAuthorizationStatus
        if status == ICAuthorizationStatus.authorized { controlAuthorized = true; return }
        if status == ICAuthorizationStatus.denied || status == ICAuthorizationStatus.restricted {
            controlAuthorized = false
            line = "Camera control is off in Settings"
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let gate = Gate()
            browser.requestControlAuthorization { status in
                Task { @MainActor in
                    self.controlAuthorized = status == ICAuthorizationStatus.authorized
                    if !self.controlAuthorized { self.line = "Camera control is off in Settings" }
                }
                gate.run { cont.resume() }
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                gate.run { cont.resume() }
            }
        }
    }

    private func adopt(_ device: ICDevice) {
        guard let camera = device as? ICCameraDevice else { return }
        let id = camera.uuidString ?? UUID().uuidString
        if links[id] != nil { return }
        let vendor = Int(camera.usbVendorID)
        let name = camera.name ?? ""
        if vendor != 0 && vendor != PTP.nikonVendor && !name.lowercased().contains("nikon") { return }
        let link = NikonLink(device: camera, arrivals: arrivals)
        camera.delegate = self
        links[id] = link
        Task {
            do {
                try await link.open()
                if let vendorOK = link.info.flatMap({ $0.model.lowercased().contains("nikon") ? true : nil }),
                   vendor != PTP.nikonVendor && vendorOK == false {
                    self.links[id] = nil
                    return
                }
                if vendor != PTP.nikonVendor && vendor != 0 {
                    let model = link.info?.model.lowercased() ?? name.lowercased()
                    if !model.contains("nikon") && !name.lowercased().contains("nikon") {
                        self.links[id] = nil
                        return
                    }
                }
                self.claimRoles()
                self.seat()
                await self.refreshStatus()
                self.probeLiveIfAsked()
            } catch {
                self.line = error.localizedDescription
                self.links[id] = nil
                self.publish()
            }
        }
    }

    private static func kept(_ saved: String) -> String {
        if saved.hasPrefix("usb-") { return saved }
        return PTP.usable(saved)
    }

    /// Seat every connected body. A saved port that is not plugged in is dropped, then open roles fill in USB order.
    private func claimRoles() {
        let tokens = Set(links.values.map(\.token))
        if !pairT.isEmpty && !tokens.contains(pairT) { pairT = "" }
        if !pairR.isEmpty && !tokens.contains(pairR) { pairR = "" }
        let loose = links.values.filter { role(of: $0.token) == nil && !$0.token.isEmpty }
            .sorted { sideRank($0) < sideRank($1) }
        var index = 0
        if pairT.isEmpty, index < loose.count {
            pairT = loose[index].token
            index += 1
        }
        if pairR.isEmpty, index < loose.count {
            pairR = loose[index].token
        }
        Disk.savePair(t: pairT, r: pairR)
    }

    private let arrivals = Arrivals()
    private func waitUntilQuiet() async {
        var last = -1
        var stable = 0
        for _ in 0..<30 {
            let count = arrivals.total
            stable = count == last ? stable + 1 : 0
            if stable >= 3 { return }
            last = count
            try? await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    private var didProbe = false
    private func probeLiveIfAsked() {
        guard !didProbe, ProcessInfo.processInfo.arguments.contains("-probeLive"), !links.isEmpty else { return }
        didProbe = true
        Task {
            let deadline = Date().addingTimeInterval(8)
            while self.links.count < 2 && Date() < deadline {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
            await self.waitUntilQuiet()
            await self.setLive(true)
            guard ProcessInfo.processInfo.arguments.contains("-probeShoot") else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            do {
                let got = try await self.capture(stamp: CaptureIndex.stampNow(), photo: Photo())
                print("FXPAN shot t=\(got[.t]?.jpeg != nil) r=\(got[.r]?.jpeg != nil)")
            } catch {
                print("FXPAN shot \(error.localizedDescription)")
            }
            print("FXPAN probe done")
            exit(0)
        }
    }

    private func role(of serial: String) -> Role? {
        if !serial.isEmpty && serial == pairT { return .t }
        if !serial.isEmpty && serial == pairR { return .r }
        return nil
    }

    private func seat() {
        detected = links.values.map { link in
            DetectedCamera(id: link.id, token: link.token, serial: link.serial, model: link.model, role: role(of: link.token))
        }.sorted { $0.model < $1.model }
    }

    private func refreshStatus() async {
        for link in links.values {
            await link.readExposure()
        }
        publish()
    }

    private func publish() {
        if simulate {
            slots[.t] = BodyState(online: true, paired: true, serial: "SIM-T", model: "D800", battery: 86, iso: "400", shutter: "1/250", fstop: "8", program: "M", wb: "Auto")
            slots[.r] = BodyState(online: true, paired: true, serial: "SIM-R", model: "D800", battery: 74, iso: "400", shutter: "1/250", fstop: "8", program: "M", wb: "Auto")
            line = "Simulator"
            onChange?()
            return
        }
        var next: [Role: BodyState] = [
            .t: BodyState(paired: !pairT.isEmpty, serial: pairT),
            .r: BodyState(paired: !pairR.isEmpty, serial: pairR),
        ]
        for link in links.values {
            guard let who = role(of: link.token) else { continue }
            next[who] = link.state(role: who, paired: true)
        }
        slots = next
        let online = Role.allCases.filter { slots[$0]?.online == true }
        if live {
            line = liveLine
        } else if online.isEmpty {
            line = links.isEmpty ? (controlAuthorized ? "No bodies on USB" : line) : "Bodies seen, not paired"
        } else if online.count == 1 {
            line = "\(online[0].rawValue) on USB"
        } else {
            line = "T and R on USB"
        }
        onChange?()
    }

    private func installSim() {
        let pair = SimScene.pair(phase: 0)
        frames[.t] = UIImage(cgImage: pair.t)
        frames[.r] = UIImage(cgImage: pair.r)
        if live { startSimClock() }
    }

    private func startSimClock() {
        simTimer?.invalidate()
        simTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.simulate, self.live else { return }
                self.simPhase += 0.15
                let pair = SimScene.pair(phase: self.simPhase)
                self.frames[.t] = UIImage(cgImage: pair.t)
                self.frames[.r] = UIImage(cgImage: pair.r)
                self.onChange?()
            }
        }
    }
}

/// ImageCapture delivers the data phase to this delegate. The completion block drops large payloads such as live view.
private final class FileReader: NSObject {
    var finish: ((Data?, Error?) -> Void)?

    @objc func didReadData(_ data: NSData, fromFile file: ICCameraFile, error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        finish?(data as Data, error)
    }
}

private final class PTPSink: NSObject {
    var finish: ((Data, Data, Error?) -> Void)?

    @objc func didSendPTPCommand(_ command: NSData, inData: NSData, response: NSData, error: NSError?, contextInfo: UnsafeMutableRawPointer?) {
        finish?(inData as Data, response as Data, error)
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    func run(_ body: () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        if done { return }
        done = true
        body()
    }
}

// MARK: - One Nikon session

@MainActor
final class Arrivals {
    private var files: [ObjectIdentifier: [ICCameraFile]] = [:]
    var total: Int { files.values.reduce(0) { $0 + $1.count } }

    func add(_ camera: ICCameraDevice, _ items: [ICCameraFile]) {
        guard !items.isEmpty else { return }
        files[ObjectIdentifier(camera), default: []].append(contentsOf: items)
    }

    func mark(_ camera: ICCameraDevice) -> Int { files[ObjectIdentifier(camera)]?.count ?? 0 }

    func since(_ camera: ICCameraDevice, _ mark: Int) -> [ICCameraFile] {
        let all = files[ObjectIdentifier(camera)] ?? []
        guard mark < all.count else { return [] }
        return Array(all.dropFirst(mark))
    }
}

@MainActor
final class NikonLink {
    let device: ICCameraDevice
    let arrivals: Arrivals
    let id: String
    private(set) var info: PTP.DeviceInfo?
    private var props: [UInt16: PTP.PropDesc] = [:]
    private var txn: UInt32 = 1
    private var chain: Task<Void, Never>?
    private(set) var inLive = false
    private var exposure = BodyState()

    var serial: String { PTP.usable(info?.serial ?? "") }

    /// Real serial when the body gives one. Otherwise the USB port, so two bodies that both say 000000 stay distinct.
    var token: String {
        if !serial.isEmpty { return serial }
        let loc = device.usbLocationID
        if loc != 0 { return "usb-\(loc)" }
        return id
    }
    var model: String {
        let raw = info?.model ?? device.name ?? "Nikon"
        return raw.replacingOccurrences(of: "Nikon DSC ", with: "")
    }

    init(device: ICCameraDevice, arrivals: Arrivals) {
        self.device = device
        self.arrivals = arrivals
        self.id = device.uuidString ?? UUID().uuidString
    }

    func state(role: Role, paired: Bool) -> BodyState {
        var s = exposure
        s.online = true
        s.paired = paired
        s.serial = serial.isEmpty ? token : serial
        s.model = model
        return s
    }

    func open() async throws {
        if !device.hasOpenSession {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                device.requestOpenSession(options: nil) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
        let reply = try await transact(PTP.Op.getDeviceInfo.rawValue, timeout: 12)
        guard reply.ok, let parsed = PTP.parseDeviceInfo(reply.data) else {
            throw PTPError.message("Could not read the camera")
        }
        info = parsed
        for prop in [PTP.Prop.battery, .compression, .whiteBalance, .fNumber, .exposureTime, .program, .iso, .isoAuto, .recordingMedia, .isoAutoHi] {
            guard parsed.properties.contains(prop.rawValue) else { continue }
            if let descReply = try? await transact(PTP.Op.getPropDesc.rawValue, params: [UInt32(prop.rawValue)]),
               descReply.ok, let desc = PTP.parsePropDesc(descReply.data) {
                props[prop.rawValue] = desc
            }
        }
        await readExposure()
    }

    func readExposure() async {
        exposure.iso = await text(.iso) { Catalog.isAuto(self.exposure.iso) ? "Auto" : String($0) } ?? exposure.iso
        if let auto = await value(.isoAuto), auto != 0 { exposure.iso = "Auto" }
        exposure.shutter = await text(.exposureTime) { Self.formatShutter($0) } ?? exposure.shutter
        exposure.fstop = await text(.fNumber) { Self.formatF($0) } ?? exposure.fstop
        exposure.program = await text(.program) { Self.formatProgram($0) } ?? exposure.program
        exposure.wb = await text(.whiteBalance) { Self.formatWB($0) } ?? exposure.wb
        if let bat = await value(.battery) { exposure.battery = Int(min(100, bat)) }
    }

    /// One open session. Each property is a PTP op on that session, not a new claim.
    func apply(_ photo: Photo) async throws {
        let light = photo.light
        if let iso = Catalog.isoValue(light.iso) {
            try? await set(.isoAuto, 0)
            try? await set(.isoAutoHi, 0)
            try await set(.iso, UInt64(iso))
        }
        try await set(.program, Self.programCode(light.program))
        if let shutter = Catalog.shutterTenThousandths(light.bulb ? "bulb" : light.shutter) {
            try await set(.exposureTime, UInt64(shutter))
        }
        if let f = Catalog.fNumberHundredths(light.fstop), light.program == "M" || light.program == "A" {
            try await set(.fNumber, UInt64(f))
        }
        try await set(.whiteBalance, Self.wbCode(photo.wb))
        try await set(.compression, Self.qualityCode(photo.drive.quality))
        await readExposure()
    }

    /// Enter live view and return. Polling is shared so one body cannot starve the other.
    /// StartLiveView answers 2019 while the mirror is still moving, and also when live view is already up.
    /// Reissuing it keeps the body busy, so wait on DeviceReady and try a frame before tearing the mode down.
    func enterLive() async -> Bool {
        inLive = true
        do {
            if await pullFrame() != nil { return true }
            let ended = try? await transact(PTP.Op.endLiveView.rawValue, timeout: 3)
            print("FXPAN \(model) end \(Self.hex(ended?.code))")
            _ = try? await transact(PTP.Op.changeMode.rawValue, params: [0], timeout: 3)
            await settle(minimum: 1.2, seconds: 8)
            let mode = try? await transact(PTP.Op.changeMode.rawValue, params: [1])
            print("FXPAN \(model) mode \(Self.hex(mode?.code))")
            await settle(minimum: 1.2, seconds: 8)
            var started = try await transact(PTP.Op.startLiveView.rawValue, timeout: 8)
            print("FXPAN \(model) start \(Self.hex(started.code))")
            if started.code == 0x2019 {
                if await pullFrame() != nil { return true }
                await settle(minimum: 0.8, seconds: 8)
                started = try await transact(PTP.Op.startLiveView.rawValue, timeout: 8)
                print("FXPAN \(model) start2 \(Self.hex(started.code))")
            }
            if started.code != PTP.ok {
                if await pullFrame() != nil { return true }
                _ = try? await transact(PTP.Op.endLiveView.rawValue, timeout: 3)
                _ = try? await transact(PTP.Op.changeMode.rawValue, params: [0], timeout: 3)
                await settle(minimum: 1.0, seconds: 6)
                inLive = false
                liveNote = "\(model) live start \(Self.hex(started.code))"
                return false
            }
            await settle(minimum: 0.4, seconds: 4)
            return true
        } catch {
            print("FXPAN \(model) live \(error.localizedDescription)")
            inLive = false
            return false
        }
    }

    /// DeviceReady often says OK before the mirror has finished. Stay until two OK replies and a minimum wait.
    private func settle(minimum: Double, seconds: Double) async {
        let start = Date()
        let deadline = start.addingTimeInterval(seconds)
        var log: [String] = []
        var last: UInt16 = 0xFFFF
        var run = 0
        var okStreak = 0
        while Date() < deadline {
            let reply = try? await transact(PTP.Op.deviceReady.rawValue, timeout: 2)
            let code = reply?.code ?? 0
            if code == last {
                run += 1
            } else {
                if last != 0xFFFF { log.append("\(Self.hex(last))x\(run)") }
                last = code
                run = 1
            }
            if code == PTP.ok { okStreak += 1 } else { okStreak = 0 }
            if okStreak >= 2 && Date().timeIntervalSince(start) >= minimum { break }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        if last != 0xFFFF { log.append("\(Self.hex(last))x\(run)") }
        print("FXPAN \(model) ready \(log.joined(separator: ","))")
    }

    /// One GetLiveView. A JPEG means the mirror is already up, even if StartLiveView said busy.
    private func pullFrame() async -> UIImage? {
        guard let reply = try? await transact(PTP.Op.getLiveView.rawValue, timeout: 6) else { return nil }
        let blob = PTP.jpeg(in: reply.data) ?? PTP.jpeg(in: reply.raw)
        guard let blob, blob.count > 64, let image = UIImage(data: blob) else { return nil }
        print("FXPAN \(model) frame \(Int(image.size.width))x\(Int(image.size.height)) luma \(Self.luma(image))")
        let url = Disk.captures.appendingPathComponent("live-\(token.filter { $0.isNumber }).jpg")
        try? blob.write(to: url)
        return image
    }

    private static func luma(_ image: UIImage) -> Int {
        guard let cg = image.cgImage else { return -1 }
        let w = 16, h = 16
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return -1 }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sum = 0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            sum += Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])
        }
        return sum / (w * h * 3)
    }

    private static func hex(_ code: UInt16?) -> String {
        guard let code else { return "none" }
        return String(format: "%04X", code)
    }

    private(set) var liveNote = ""
    private var liveMisses = 0

    func nextFrame() async -> UIImage? {
        guard inLive else { return nil }
        let reply: PTP.Reply
        do {
            reply = try await transact(PTP.Op.getLiveView.rawValue, timeout: 6)
        } catch {
            noteLive("\(model) live \(error.localizedDescription)")
            return nil
        }
        let blob = PTP.jpeg(in: reply.data) ?? PTP.jpeg(in: reply.raw)
        if let blob, blob.count > 64, let image = UIImage(data: blob) {
            liveMisses += 1
            if liveMisses == 1 {
                print("FXPAN \(model) frame \(Int(image.size.width))x\(Int(image.size.height))")
            }
            liveNote = "ok"
            return image
        }
        if reply.code == 0xA00B {
            _ = try? await transact(PTP.Op.startLiveView.rawValue, timeout: 4)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        let head = reply.data.prefix(12).map { String(format: "%02X", $0) }.joined()
        noteLive("\(model) live \(reply.data.count)b \(String(format: "%04X", reply.code)) \(head)")
        return nil
    }

    private func noteLive(_ text: String) {
        liveMisses += 1
        guard liveMisses <= 3 else { return }
        liveNote = text
        print("FXPAN \(text)")
    }

    func stopLive() async {
        inLive = false
        _ = try? await transact(PTP.Op.endLiveView.rawValue, timeout: 4)
        _ = try? await transact(PTP.Op.changeMode.rawValue, params: [0], timeout: 4)
        await settle(minimum: 1.2, seconds: 8)
    }

    func shoot(stamp: String, role: Role, photo: Photo) async throws -> Grabbed {
        await stopLive()
        let mark = arrivals.mark(device)
        // The card is where these bodies actually write. The RAM capture command answers OK and then keeps the file.
        try? await set(.recordingMedia, 0)
        try await apply(photo)
        await settle(minimum: 0.4, seconds: 4)
        let before = (try? await objectHandles()) ?? []
        var reply = try await transact(PTP.Op.initiateCapture.rawValue, params: [0, 0], timeout: 25)
        print("FXPAN \(model) capture \(Self.hex(reply.code))")
        if reply.code == 0x2019 {
            await settle(minimum: 1.5, seconds: 12)
            reply = try await transact(PTP.Op.initiateCapture.rawValue, params: [0, 0], timeout: 25)
            print("FXPAN \(model) capture2 \(Self.hex(reply.code))")
        }
        if !reply.ok {
            try? await set(.recordingMedia, 1)
            await settle(minimum: 0.4, seconds: 4)
            reply = try await transact(PTP.Op.captureSDRAM.rawValue, params: [0xFFFF_FFFF], timeout: 25)
            print("FXPAN \(model) captureRAM \(Self.hex(reply.code))")
        }
        guard reply.ok else { throw PTPError.message("\(role.rawValue) did not fire \(Self.hex(reply.code))") }
        var handles: [UInt32] = []
        if let handle = reply.params.first, handle != 0, handle != 0xFFFF_FFFF {
            handles.append(handle)
        }
        let deadline = Date().addingTimeInterval(4)
        while handles.isEmpty && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000)
            _ = try? await transact(PTP.Op.deviceReady.rawValue, timeout: 1)
            if let ev = try? await transact(PTP.Op.getEvent.rawValue), ev.ok {
                handles.append(contentsOf: Self.eventHandles(ev.data))
            }
        }
        if handles.isEmpty {
            let after = (try? await objectHandles()) ?? []
            handles = after.filter { !before.contains($0) }
        }
        if handles.isEmpty {
            let fresh = await waitArrival(after: mark)
            if let grabbed = try await grabbed(from: fresh, stamp: stamp, role: role) {
                return grabbed
            }
            throw PTPError.message("\(role.rawValue) fired, no file came back")
        }
        var jpegURL: URL?
        var nefURL: URL?
        for handle in handles.reversed() {
            if jpegURL != nil && nefURL != nil { break }
            let file = try await transact(PTP.Op.getObject.rawValue, params: [handle], timeout: 60)
            guard file.ok, !file.data.isEmpty else { continue }
            if file.data.starts(with: [0xFF, 0xD8]) {
                let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).jpg")
                try file.data.write(to: url, options: .atomic)
                jpegURL = url
            } else {
                let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).nef")
                try file.data.write(to: url, options: .atomic)
                nefURL = url
                if jpegURL == nil, let jpg = PTP.jpeg(in: file.data), jpg.count > 20_000 {
                    let preview = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).jpg")
                    try jpg.write(to: preview, options: .atomic)
                    jpegURL = preview
                }
            }
        }
        if jpegURL == nil && nefURL == nil { throw PTPError.message("\(role.rawValue) file was empty") }
        return Grabbed(jpeg: jpegURL, nef: nefURL)
    }

    private func waitArrival(after mark: Int) async -> [ICCameraFile] {
        let deadline = Date().addingTimeInterval(8)
        while Date() < deadline {
            let fresh = arrivals.since(device, mark)
            if fresh.contains(where: { ($0.name ?? "").uppercased().hasSuffix("JPG") }) { return fresh }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return arrivals.since(device, mark)
    }

    private func grabbed(from files: [ICCameraFile], stamp: String, role: Role) async throws -> Grabbed? {
        guard !files.isEmpty else { return nil }
        var jpegURL: URL?
        var nefURL: URL?
        for file in files.reversed() {
            if jpegURL != nil && nefURL != nil { break }
            let name = (file.name ?? "").uppercased()
            let data = try await readFile(file)
            guard !data.isEmpty else { continue }
            if name.hasSuffix("JPG") || data.starts(with: [0xFF, 0xD8]) {
                let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).jpg")
                try data.write(to: url, options: .atomic)
                jpegURL = url
            } else if name.hasSuffix("NEF") {
                let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).nef")
                try data.write(to: url, options: .atomic)
                nefURL = url
            }
        }
        if jpegURL == nil && nefURL == nil { return nil }
        print("FXPAN \(role.rawValue) saved \(files.map { $0.name ?? "?" }.joined(separator: ","))")
        return Grabbed(jpeg: jpegURL, nef: nefURL)
    }

    private var fileReader: FileReader?

    private func readFile(_ file: ICCameraFile) async throws -> Data {
        let sink = FileReader()
        fileReader = sink
        return try await withCheckedThrowingContinuation { cont in
            let gate = Gate()
            sink.finish = { data, error in
                gate.run {
                    if let error { cont.resume(throwing: error) }
                    else { cont.resume(returning: data ?? Data()) }
                }
            }
            device.requestReadData(from: file, atOffset: 0, length: off_t(file.fileSize), readDelegate: sink, didReadDataSelector: #selector(FileReader.didReadData(_:fromFile:error:contextInfo:)), contextInfo: nil)
            Task {
                try? await Task.sleep(nanoseconds: 45_000_000_000)
                gate.run { cont.resume(throwing: PTPError.timeout) }
            }
        }
    }

    // MARK: PTP

    private func set(_ prop: PTP.Prop, _ value: UInt64) async throws {
        if let supported = info?.properties, !supported.isEmpty, !supported.contains(prop.rawValue) { return }
        let desc = props[prop.rawValue]
        let type = desc?.dataType ?? Self.fallbackType(prop)
        var chosen = value
        if let enums = desc?.enums, !enums.isEmpty, !enums.contains(value) {
            chosen = PTP.nearest(value, in: enums) ?? value
        }
        let reply = try await transact(PTP.Op.setProp.rawValue, params: [UInt32(prop.rawValue)], out: PTP.encode(chosen, type: type))
        if reply.ok {
            props[prop.rawValue]?.current = chosen
            return
        }
        // A005 the body will not take this property (mode dial, or no lens for aperture). Keep shooting.
        if reply.code == 0xA005 || reply.code == 0xA00A || reply.code == 0x2005 || reply.code == 0x2006 {
            print("FXPAN skip \(model) prop \(String(format: "%04X", prop.rawValue)) \(String(format: "%04X", reply.code))")
            return
        }
        throw PTPError.refused(reply.code)
    }

    private func value(_ prop: PTP.Prop) async -> UInt64? {
        if let supported = info?.properties, !supported.isEmpty, !supported.contains(prop.rawValue) {
            return props[prop.rawValue]?.current
        }
        guard let reply = try? await transact(PTP.Op.getProp.rawValue, params: [UInt32(prop.rawValue)]), reply.ok else {
            return props[prop.rawValue]?.current
        }
        let type = props[prop.rawValue]?.dataType ?? Self.fallbackType(prop)
        var reader = PTP.Reader(data: reply.data)
        return reader.readValue(type) ?? props[prop.rawValue]?.current
    }

    private func text(_ prop: PTP.Prop, _ format: (UInt64) -> String) async -> String? {
        guard let v = await value(prop) else { return nil }
        return format(v)
    }

    private func objectHandles() async throws -> [UInt32] {
        let storages = try await transact(PTP.Op.getStorageIDs.rawValue)
        var ids = Self.words(storages.data)
        if ids.isEmpty { ids = [0xFFFF_FFFF] }
        var all: [UInt32] = []
        for id in ids {
            let reply = try await transact(PTP.Op.getObjectHandles.rawValue, params: [id, 0, 0xFFFF_FFFF])
            all.append(contentsOf: Self.words(reply.data))
        }
        return all
    }

    private func transact(_ code: UInt16, params: [UInt32] = [], out: Data? = nil, timeout: Double = 8) async throws -> PTP.Reply {
        let transaction = txn
        txn &+= 1
        let command = PTP.command(code: code, transaction: transaction, params: params)
        return try await enqueue {
            try await self.roundTrip(command, out: out, timeout: timeout)
        }
    }

    private func enqueue(_ work: @escaping @MainActor () async throws -> PTP.Reply) async throws -> PTP.Reply {
        let previous = chain
        return try await withCheckedThrowingContinuation { cont in
            chain = Task { @MainActor in
                await previous?.value
                do {
                    cont.resume(returning: try await work())
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    private var sink: PTPSink?

    private func roundTrip(_ command: Data, out: Data?, timeout: Double) async throws -> PTP.Reply {
        let device = self.device
        let sink = PTPSink()
        self.sink = sink
        return try await withCheckedThrowingContinuation { cont in
            let gate = Gate()
            sink.finish = { data, response, error in
                gate.run {
                    if let error {
                        cont.resume(throwing: error)
                    } else {
                        cont.resume(returning: PTP.reply(data: data, response: response))
                    }
                }
            }
            device.requestSendPTPCommand(
                command,
                outData: out,
                sendCommandDelegate: sink,
                didSendCommand: #selector(PTPSink.didSendPTPCommand(_:inData:response:error:contextInfo:)),
                contextInfo: nil
            )
            Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                gate.run { cont.resume(throwing: PTPError.timeout) }
            }
        }
    }

    private static func words(_ data: Data) -> [UInt32] {
        guard data.count >= 4 else { return [] }
        let n = min(Int(data.u32(0)), (data.count - 4) / 4)
        var out: [UInt32] = []
        for i in 0..<n {
            out.append(data.u32(4 + i * 4))
        }
        return out
    }

    private static func eventHandles(_ data: Data) -> [UInt32] {
        guard data.count >= 2 else { return [] }
        let count = min(Int(data.u16(0)), 32)
        var i = 2
        var out: [UInt32] = []
        for _ in 0..<count {
            if i + 6 > data.count { break }
            let code = data.u16(i)
            let param = data.u32(i + 2)
            // 0x4002 is a card file. 0xC101 is Nikon's "added in SDRAM" when the shot stays on the iPad.
            if (code == PTP.objectAdded || code == 0xC101), param != 0 { out.append(param) }
            i += 6
        }
        return out
    }

    private static func fallbackType(_ prop: PTP.Prop) -> UInt16 {
        switch prop {
        case .battery, .compression, .recordingMedia, .isoAuto, .isoAutoHi: return 0x0002
        case .exposureTime: return 0x0006
        default: return 0x0004
        }
    }

    private static func formatShutter(_ v: UInt64) -> String {
        if v == 0 || v == 0xFFFF_FFFF { return "bulb" }
        if v >= 10_000 {
            let sec = Double(v) / 10_000
            if abs(sec - sec.rounded()) < 0.05 { return String(Int(sec.rounded())) }
            return String(format: "%g", sec)
        }
        let denom = max(1, Int((10_000.0 / Double(max(v, 1))).rounded()))
        return "1/\(denom)"
    }

    private static func formatF(_ v: UInt64) -> String {
        let n = Double(v) / 100
        if abs(n - n.rounded()) < 0.05 { return String(Int(n.rounded())) }
        return String(format: "%g", n)
    }

    private static func formatProgram(_ v: UInt64) -> String {
        switch v {
        case 1: return "M"
        case 2: return "P"
        case 3: return "A"
        case 4: return "S"
        default: return String(v)
        }
    }

    private static func formatWB(_ v: UInt64) -> String {
        switch v {
        case 2: return "Auto"
        case 4: return "Daylight"
        case 5: return "Fluorescent"
        case 6: return "Incandescent"
        case 7: return "Flash"
        case 0x8010: return "Cloudy"
        case 0x8011: return "Shade"
        default: return String(v)
        }
    }

    private static func programCode(_ v: String) -> UInt64 {
        switch v {
        case "P": return 2
        case "A": return 3
        case "S": return 4
        default: return 1
        }
    }

    private static func wbCode(_ v: String) -> UInt64 {
        switch v {
        case "Sunny": return 4
        case "Fluorescent": return 5
        case "Tungsten": return 6
        case "Flash": return 7
        case "Cloudy": return 0x8010
        case "Shade": return 0x8011
        default: return 2
        }
    }

    private static func qualityCode(_ v: String) -> UInt64 {
        switch v {
        case "JPEG Normal": return 1
        case "JPEG Fine": return 2
        case "NEF (Raw)": return 4
        default: return 7
        }
    }
}

enum SimScene {
    static func pair(phase: CGFloat) -> (t: CGImage, r: CGImage) {
        let w = 1200, h = 800, ol = 240
        let shared = strip(width: ol, height: h)
        let t = canvas(w, h) { ctx in
            UIColor(hex: 0xC4A46A).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            shared.draw(in: CGRect(x: 0, y: 0, width: ol, height: h))
            mark(ctx, "T", x: CGFloat(w) - 180, y: 80, color: UIColor(hex: 0x9A5CFF))
            moving(ctx, phase: phase, x: CGFloat(w) * 0.62)
        }
        let flipped = UIImage(cgImage: Stitcher.flop(shared.cgImage!))
        let r = canvas(w, h) { ctx in
            UIColor(hex: 0x6E8CA8).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            flipped.draw(in: CGRect(x: 0, y: 0, width: ol, height: h))
            mark(ctx, "R", x: CGFloat(w) - 180, y: 80, color: UIColor(hex: 0xD8712F))
            moving(ctx, phase: phase + 1.2, x: CGFloat(w) * 0.62)
        }
        return (t, r)
    }

    private static func strip(width: Int, height: Int) -> UIImage {
        canvasImage(width, height) { ctx in
            for i in 0..<12 {
                let shade = CGFloat(i) / 11
                UIColor(white: 0.15 + shade * 0.75, alpha: 1).setFill()
                let x = CGFloat(i) / 12 * CGFloat(width)
                ctx.fill(CGRect(x: x, y: 0, width: CGFloat(width) / 12 + 1, height: CGFloat(height)))
            }
            UIColor(hex: 0xE22B2B).setFill()
            ctx.fillEllipse(in: CGRect(x: CGFloat(width) * 0.35, y: CGFloat(height) * 0.38, width: 70, height: 70))
            UIColor(hex: 0x1B1405).setFill()
            ctx.fill(CGRect(x: 18, y: CGFloat(height) * 0.2, width: 16, height: CGFloat(height) * 0.55))
        }
    }

    private static func mark(_ ctx: CGContext, _ text: String, x: CGFloat, y: CGFloat, color: UIColor) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 64, weight: .medium),
            .foregroundColor: color,
        ]
        NSAttributedString(string: text, attributes: attrs).draw(at: CGPoint(x: x, y: y))
    }

    private static func moving(_ ctx: CGContext, phase: CGFloat, x: CGFloat) {
        let y = CGFloat(heightOffset(phase))
        UIColor.white.withAlphaComponent(0.85).setFill()
        ctx.fillEllipse(in: CGRect(x: x, y: y, width: 36, height: 36))
    }

    private static func heightOffset(_ phase: CGFloat) -> CGFloat {
        180 + sin(phase) * 140
    }

    private static func canvas(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> CGImage {
        canvasImage(w, h, draw).cgImage!
    }

    private static func canvasImage(_ w: Int, _ h: Int, _ draw: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format).image { ctx in
            draw(ctx.cgContext)
        }
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
