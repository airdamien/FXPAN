import CoreImage
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
    var link = ""
}

struct DetectedCamera: Identifiable, Equatable {
    var id: String
    var token: String
    var serial: String
    var model: String
    var role: Role?
    var link = ""
}

struct Grabbed {
    var jpeg: URL?
    var nef: URL?
}

/// USB PTP for the paired Nikons, plus a no-cable scene so the UI runs in the Simulator.
@MainActor
final class CameraHub: NSObject, ICDeviceBrowserDelegate, ICCameraDeviceDelegate {
    var onChange: (() -> Void)?
    var onSeat: (() -> Void)?
    /// A body finished opening. The app pushes the saved exposure back on.
    var onReady: (() -> Void)?

    var simulate = false {
        didSet { publish(); if simulate { installSim() } else { frames = realFrames } }
    }

    private(set) var slots: [Role: BodyState] = [.t: BodyState(), .r: BodyState()]
    private(set) var detected: [DetectedCamera] = []
    private(set) var frames: [Role: UIImage] = [:]
    /// When each live frame was requested from its body, for measuring how old the picture on screen is.
    private(set) var frameAsked: [Role: CFAbsoluteTime] = [:]
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
    /// Gaussian radius applied to the simulator frames. The focus review holds the scene and walks this out and back.
    var focusBlur: CGFloat = 0
    var focusHold = false
    /// While a focus review is pushing its own frames, the live clock stays quiet.
    var focusDrive = false
    private var started = false
    private var front = true
    private var livePoll: Task<Void, Never>?
    private var liveLine = "Live"
    /// Set while the 10-pin pulse has USB closed. A close callback must not reopen the bodies in that window.
    private var usbHeld = false
    /// Set while idle has closed the sessions so the bodies can sleep. A close callback must not reopen them.
    private var idling = false
    private var liveBeforeIdle = false

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

    /// Stop live view and drop the sessions so the bodies are not held awake.
    func idleDown() async {
        guard started, !simulate, !idling else { return }
        liveBeforeIdle = live
        idling = true
        await setLive(false)
        for link in Array(links.values) {
            await link.closeForSync()
        }
        publish()
    }

    /// Open the sessions again. Live view comes back only if it was on before sleep.
    func wakeFromIdle() async {
        guard idling else { return }
        let resume = liveBeforeIdle
        idling = false
        await foreground()
        if resume { await setLive(true) }
    }

    private func seenDevices() -> [ICDevice] {
        browser.devices ?? []
    }

    /// iOS closes camera sessions while the app is away and does not always deliver a removal. Drop anything the browser no longer lists, and reopen a session that closed while the body is still plugged in.
    func foreground() async {
        guard started, !simulate else { return }
        front = true
        let ids = Set(seenDevices().compactMap(\.uuidString))
        for id in Array(links.keys) where !ids.contains(id) {
            links[id]?.noteSessionClosed()
            links.removeValue(forKey: id)
        }
        forgetMissingFrames()
        seat()
        publish()
        if !usbHeld && !idling {
            for link in Array(links.values) where !link.sessionUp || !link.device.hasOpenSession {
                do {
                    try await link.open()
                } catch {
                    links[link.id] = nil
                }
            }
        }
        for device in seenDevices() { adopt(device) }
        if !links.values.contains(where: \.inLive) {
            live = false
            livePoll?.cancel()
            livePoll = nil
        }
        forgetMissingFrames()
        seat()
        publish()
        onReady?()
    }
    func background() {
        guard started, !simulate else { return }
        front = false
        live = false
        livePoll?.cancel()
        livePoll = nil
        for link in links.values { link.leaveLive() }
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
        guard !simulate, photo.exposes, !usbHeld, !idling else { return }
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
            let started: [(String, Bool)] = await withTaskGroup(of: (String, Bool).self) { group in
                for link in bodies {
                    let name = role(of: link.token)?.rawValue ?? link.model
                    group.addTask { @MainActor in (name, await link.enterLive()) }
                }
                var rows: [(String, Bool)] = []
                for await row in group { rows.append(row) }
                return rows
            }
            let up = started.filter(\.1).map(\.0).sorted()
            let down = started.filter { !$0.1 }.map(\.0).sorted()
            guard !up.isEmpty else {
                line = "Live view refused"
                publish()
                return
            }
            live = true
            liveLine = down.isEmpty ? "Live" : "Live · \(down.joined(separator: ", ")) refused"
            publish()
            let polled = bodies.filter(\.inLive)
            livePoll = Task { [weak self] in
                // Each body polls on its own loop, so a slow reply from one never holds back the other's next frame.
                await withTaskGroup(of: Void.self) { group in
                    for link in polled {
                        group.addTask { @MainActor [weak self] in
                            while let self, self.live, link.inLive, !Task.isCancelled {
                                let image = await link.nextFrame()
                                if !self.live || Task.isCancelled { break }
                                if let image {
                                    self.deliver(link, image)
                                    continue
                                }
                                if self.frames.isEmpty, !link.liveNote.isEmpty {
                                    self.liveLine = link.liveNote
                                    self.publish()
                                }
                                try? await Task.sleep(nanoseconds: 30_000_000)
                            }
                        }
                    }
                }
            }
        } else {
            live = false
            let poll = livePoll
            livePoll = nil
            await Self.each(bodies) { await $0.stopLive() }
            await poll?.value
            publish()
        }
    }

    /// Run the same step on every body at once. Each body has its own session and command chain.
    private static func each(_ links: [NikonLink], _ work: @escaping @MainActor (NikonLink) async -> Void) async {
        await withTaskGroup(of: Void.self) { group in
            for link in links {
                group.addTask { @MainActor in await work(link) }
            }
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
        frameAsked[who] = link.frameAsked
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
        if photo.drive.release == "sync" {
            return try await captureSync(stamp: stamp, photo: photo)
        }
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

    /// Arm both bodies, drop USB so the D800s honor the 10-pin, pulse the Zero, then download.
    private func captureSync(stamp: String, photo: Photo) async throws -> [Role: Grabbed] {
        let bodies = links.values.filter { role(of: $0.token) != nil }
        guard !bodies.isEmpty else { throw PTPError.message("No paired body on USB") }
        let armed: [(NikonLink, Role)] = bodies.compactMap { link in role(of: link.token).map { (link, $0) } }
        var armFailure: Error?
        await Self.each(armed.map(\.0)) { link in
            do { try await link.armSync(photo) } catch { armFailure = armFailure ?? error }
        }
        if let armFailure { throw armFailure }
        usbHeld = true
        defer { usbHeld = false }
        await Self.each(armed.map(\.0)) { await $0.closeForSync() }
        try await Task.sleep(nanoseconds: 800_000_000)
        let reply: String
        do {
            reply = try await SyncLink.fire(photo)
        } catch {
            await Self.each(armed.map(\.0)) { try? await $0.open() }
            throw error
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        await Self.each(armed.map(\.0)) { try? await $0.open() }
        var out: [Role: Grabbed] = [:]
        var failures: [String] = []
        await withTaskGroup(of: Result<(Role, Grabbed), Error>.self) { group in
            for row in armed {
                group.addTask {
                    do {
                        return .success((row.1, try await row.0.takeRAM(stamp: stamp, role: row.1)))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let pair): out[pair.0] = pair.1
                case .failure(let error): failures.append(error.localizedDescription)
                }
            }
        }
        if out.isEmpty {
            throw PTPError.message(failures.first ?? "Sync pulsed, no file came back")
        }
        print("FXPAN sync \(reply)")
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
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        let key = device.uuidString ?? ""
        Task { @MainActor in
            guard let link = self.links[key] else { return }
            link.noteSessionClosed()
            let stillThere = self.seenDevices().contains { $0.uuidString == key }
            if stillThere && self.front && !self.usbHeld && !self.idling {
                do { try await link.open() } catch { self.links[key] = nil }
            } else if !stillThere {
                self.links[key] = nil
            }
            if !self.links.values.contains(where: \.inLive) {
                self.live = false
                self.livePoll?.cancel()
                self.livePoll = nil
            }
            self.forgetMissingFrames()
            self.seat()
            self.publish()
        }
    }
    nonisolated func didRemove(_ device: ICDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        // Shots live in camera RAM. The card catalog is not part of the release.
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
        let link = NikonLink(device: camera)
        camera.delegate = self
        links[id] = link
        seat()
        publish()
        Task {
            if self.idling { return }
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
                self.onReady?()
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
            DetectedCamera(id: link.id, token: link.token, serial: link.serial, model: link.model, role: role(of: link.token), link: link.linkLabel)
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
            onSeat?()
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
            if links.values.contains(where: \.sessionUp) {
                line = "Bodies seen, not paired"
            } else {
                line = controlAuthorized ? "No bodies on USB" : line
            }
        } else if online.count == 1 {
            line = "\(online[0].rawValue) on USB"
        } else {
            line = "T and R on USB"
        }
        onChange?()
        onSeat?()
    }

    private func forgetMissingFrames() {
        for role in Role.allCases {
            let token = role == .t ? pairT : pairR
            let alive = links.values.contains { $0.token == token && $0.sessionUp }
            if !alive {
                realFrames[role] = nil
                frames[role] = nil
            }
        }
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
                guard let self, self.simulate, self.live, !self.focusDrive else { return }
                self.pushSimFrame()
            }
        }
    }

    func pushSimFrame() {
        guard simulate else { return }
        if !focusHold { simPhase += 0.15 }
        let pair = SimScene.pair(phase: simPhase)
        frames[.t] = Self.softened(pair.t, focusBlur)
        frames[.r] = Self.softened(pair.r, focusBlur)
        onChange?()
    }

    private static func softened(_ image: CGImage, _ radius: CGFloat) -> UIImage {
        UIImage(cgImage: FrameBlur.image(image, radius: radius))
    }
}

enum FrameBlur {
    private static let context = CIContext(options: nil)

    static func image(_ image: CGImage, radius: CGFloat) -> CGImage {
        guard radius > 0.15 else { return image }
        let input = CIImage(cgImage: image)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: input.extent)
        return context.createCGImage(blurred, from: input.extent) ?? image
    }
}

/// PTP timing lines in Application Support/FXPAN/ptp-trace.txt. Console output is lost while the phone sits on the camera hub.
enum Trace {
    private static let url = Disk.support.appendingPathComponent("ptp-trace.txt")

    static func line(_ text: String) {
        print(text)
        let stamp = String(format: "%.3f ", Date().timeIntervalSince1970)
        guard let data = (stamp + text + "\n").data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
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
        guard claim() else { return }
        body()
    }

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
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
    let id: String
    private(set) var info: PTP.DeviceInfo?
    private var props: [UInt16: PTP.PropDesc] = [:]
    private var txn: UInt32 = 1
    private var chain: Task<Void, Never>?
    private(set) var inLive = false
    private(set) var sessionUp = false
    private(set) var linkLabel = ""
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

    init(device: ICCameraDevice) {
        self.device = device
        self.id = device.uuidString ?? UUID().uuidString
    }

    func state(role: Role, paired: Bool) -> BodyState {
        var s = exposure
        s.online = sessionUp
        s.paired = paired
        s.serial = serial.isEmpty ? token : serial
        s.model = model
        s.link = linkLabel
        return s
    }

    func leaveLive() { inLive = false }

    func noteSessionClosed() {
        sessionUp = false
        inLive = false
    }

    func open() async throws {
        if sessionUp && device.hasOpenSession { return }
        if let opening {
            try await opening.value
            if sessionUp && device.hasOpenSession { return }
        }
        let task = Task { try await self.openSession() }
        opening = task
        do {
            try await task.value
            opening = nil
        } catch {
            opening = nil
            throw error
        }
    }

    private var opening: Task<Void, Error>?

    private func openSession() async throws {
        if !device.hasOpenSession {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                // Tether first. A full card catalog walks every file and the PTP pipe times out behind it.
                let tether = ICSessionOptions(rawValue: "ICEnumerationPrioritizeTethering")
                device.requestOpenSession(options: [tether: true]) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
        }
        let reply = try await transact(PTP.Op.getDeviceInfo.rawValue, timeout: 12)
        guard reply.ok, let parsed = PTP.parseDeviceInfo(reply.data) else {
            throw PTPError.message("Could not read the camera")
        }
        info = parsed
        sessionUp = true
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
    private(set) var frameAsked: CFAbsoluteTime = 0
    private var liveMisses = 0

    private var liveClock: (count: Int, total: Double, worst: Double, since: CFAbsoluteTime) = (0, 0, 0, 0)

    private func clockFrame(_ seconds: Double, bytes: Int) {
        if liveClock.count == 0 { liveClock.since = CFAbsoluteTimeGetCurrent() }
        liveClock.count += 1
        liveClock.total += seconds
        liveClock.worst = max(liveClock.worst, seconds)
        guard liveClock.count >= 30 else { return }
        let wall = CFAbsoluteTimeGetCurrent() - liveClock.since
        Trace.line(String(format: "FXPAN %@ %@ live %.1f fps, ptp avg %.0f ms max %.0f ms, %d KB", model, String(token.suffix(4)),
                     Double(liveClock.count) / max(wall, 0.001), liveClock.total / Double(liveClock.count) * 1000, liveClock.worst * 1000, bytes >> 10))
        liveClock = (0, 0, 0, 0)
    }

    func nextFrame() async -> UIImage? {
        guard inLive else { return nil }
        let reply: PTP.Reply
        let started = CFAbsoluteTimeGetCurrent()
        do {
            reply = try await transact(PTP.Op.getLiveView.rawValue, timeout: 6)
        } catch {
            noteLive("\(model) live \(error.localizedDescription)")
            return nil
        }
        clockFrame(CFAbsoluteTimeGetCurrent() - started, bytes: reply.raw.count)
        let blob = PTP.jpeg(in: reply.data) ?? PTP.jpeg(in: reply.raw)
        if let blob, blob.count > 64, let image = UIImage(data: blob) {
            liveMisses += 1
            if liveMisses == 1 {
                print("FXPAN \(model) frame \(Int(image.size.width))x\(Int(image.size.height))")
            }
            liveNote = "ok"
            frameAsked = started
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

    /// Point the release at camera RAM and empty what is already parked there.
    /// The body hands RAM frames back oldest first, so a leftover would be saved as the new shot.
    func armSync(_ photo: Photo) async throws {
        try await ensureSession()
        try await aimRAM(photo)
        await drainRAM()
    }

    private func ensureSession() async throws {
        if sessionUp && device.hasOpenSession { return }
        try await open()
    }

    private func aimRAM(_ photo: Photo) async throws {
        try await set(.recordingMedia, 1)
        try await apply(photo)
        try await set(.recordingMedia, 1)
        if let media = await value(.recordingMedia), media != 1 {
            throw PTPError.message("\(model) stayed on the card")
        }
    }

    func closeForSync() async {
        inLive = false
        guard device.hasOpenSession else {
            sessionUp = false
            return
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            device.requestCloseSession(options: nil) { _ in cont.resume() }
        }
        sessionUp = false
    }

    // MARK: Camera RAM
    //
    // libgphoto2 camera_nikon_capture and its Nikon event loop are the reference:
    // ObjectAddedInSDRAM (0xC101) or ObjectAdded (0x4002) names the new frame, and a parameter of 0 means handle 0xFFFF0001.
    // The host reads ObjectInfo, then the object. In burst and NEF+JPEG the firmware hands the next file out on that same handle,
    // either once the read finishes or once the host deletes it, so the slot is checked again after each step.
    // ParentObject 0 marks a SDRAM object. DeleteObject releases it, with 0x90C3 as the Nikon fallback.

    private struct RAMFile: Equatable {
        var handle: UInt32
        var format: UInt16
        var size: UInt32
        var parent: UInt32
        var name: String
        var inRAM: Bool { parent == 0 || handle == PTP.sdramHandle || handle == PTP.sdramHandle2 }
    }

    /// Download every file this release put in camera RAM. NEF+JPEG is two objects, read one after the other.
    func takeRAM(stamp: String, role: Role) async throws -> Grabbed {
        try await ensureSession()
        let expect = await expectedFiles()
        var jpegURL: URL?
        var nefURL: URL?
        var got: [RAMFile] = []
        var freed: [RAMFile] = []
        var failed: [RAMFile] = []
        var misses: [String] = []
        let start = Date()
        var firstAt: Date?
        while true {
            if let expect, got.count >= expect { break }
            if let firstAt {
                if Date().timeIntervalSince(firstAt) > (expect == nil ? 2 : 10) { break }
            } else if Date().timeIntervalSince(start) > 20 {
                break
            }
            var handles: [UInt32] = []
            for handle in await ramEvents() + [PTP.sdramHandle, PTP.sdramHandle2] where !handles.contains(handle) {
                handles.append(handle)
            }
            var read = false
            for handle in handles {
                guard let info = await ramInfo(handle) else { continue }
                if got.contains(info) {
                    if !freed.contains(info) {
                        freed.append(info)
                        await release(info)
                    }
                    continue
                }
                if failed.filter({ $0 == info }).count >= 2 { continue }
                print(String(format: "FXPAN %@ ram %08X fmt %04X %u bytes %@", model, handle, info.format, info.size, info.name))
                let data = try await readObject(info)
                guard data.count == Int(info.size) else {
                    failed.append(info)
                    misses.append(String(format: "%08X %d of %u", handle, data.count, info.size))
                    continue
                }
                try keep(data, stamp: stamp, role: role, jpegURL: &jpegURL, nefURL: &nefURL)
                got.append(info)
                if firstAt == nil { firstAt = Date() }
                read = true
                if let now = await ramInfo(handle), now == info {
                    freed.append(info)
                    await release(info)
                }
                break
            }
            if !read { try? await Task.sleep(nanoseconds: 150_000_000) }
        }
        print("FXPAN \(model) ram kept jpeg=\(jpegURL != nil) nef=\(nefURL != nil) expect=\(expect.map(String.init) ?? "?") \(String(format: "%.1fs", Date().timeIntervalSince(start)))")
        if jpegURL == nil && nefURL == nil {
            let why = misses.isEmpty ? "no frame in camera RAM" : "short read \(misses.joined(separator: ", "))"
            throw PTPError.message("\(role.rawValue) \(why)")
        }
        await emptyRAM()
        return Grabbed(jpeg: jpegURL, nef: nefURL)
    }

    /// Nikon Compression 0x5004, as libgphoto2 lists it: 0–2 JPEG, 3 TIFF, 4 NEF, 5–7 NEF plus a JPEG.
    private func expectedFiles() async -> Int? {
        guard let v = await value(.compression) else { return nil }
        switch v {
        case 0...4: return 1
        case 5...7: return 2
        default: return nil
        }
    }

    /// One Nikon GetEvent. The frame handles it names, with parameter 0 read as 0xFFFF0001.
    private func ramEvents() async -> [UInt32] {
        guard let ev = try? await transact(PTP.Op.getEvent.rawValue, timeout: 4), ev.ok else { return [] }
        let batch = Self.events(ev.data)
        guard !batch.isEmpty else { return [] }
        print("FXPAN \(model) events \(Self.eventBrief(ev.data))")
        var out: [UInt32] = []
        for event in batch {
            switch event.code {
            case PTP.addedInRAM, PTP.objectAdded, PTP.requestTransfer:
                out.append(event.param == 0 ? PTP.sdramHandle : event.param)
            default:
                break
            }
        }
        return out
    }

    /// ObjectInfo: StorageID @0, format @4, compressed size @8, ParentObject @38, filename @52. GetObjectInfo fails on an empty slot.
    private func ramInfo(_ handle: UInt32) async -> RAMFile? {
        guard let reply = try? await transact(PTP.Op.getObjectInfo.rawValue, params: [handle], timeout: 6),
              reply.ok, reply.data.count >= 53 else { return nil }
        let data = reply.data
        let format = data.u16(4)
        let size = data.u32(8)
        guard format != 0x3001, size > 0 else { return nil }
        var reader = PTP.Reader(data: data)
        reader.i = 52
        let name = reader.ptpString() ?? ""
        return RAMFile(handle: handle, format: format, size: size, parent: data.u32(38), name: name)
    }

    /// Release a frame that is still the one we saved. When the twin has already moved into the handle, it stays.
    private func release(_ info: RAMFile) async {
        guard info.inRAM else { return }
        let gone = try? await transact(PTP.Op.deleteObject.rawValue, params: [info.handle, 0], timeout: 8)
        var line = String(format: "FXPAN %@ release %08X delete %@", model, info.handle, Self.hex(gone?.code ?? 0))
        if let gone, !gone.ok, gone.code != 0x2009, gone.code != 0x2013 {
            let cancel = try? await transact(PTP.Op.deleteSDRAM.rawValue, params: [info.handle], timeout: 8)
            line += " cancel " + Self.hex(cancel?.code ?? 0)
        }
        print(line)
    }

    /// 0x90C3 with parameter 0 deletes every SDRAM image. Only used once this shot's files are saved, so the body leaves transfer.
    private func emptyRAM() async {
        let one = await ramInfo(PTP.sdramHandle)
        let two = one == nil ? await ramInfo(PTP.sdramHandle2) : nil
        guard one != nil || two != nil else { return }
        let wiped = try? await transact(PTP.Op.deleteSDRAM.rawValue, params: [0], timeout: 8)
        print("FXPAN \(model) ram wipe \(Self.hex(wiped?.code ?? 0))")
        await settle(minimum: 0, seconds: 3)
    }

    /// Empty frames parked in camera RAM before a new release. They go to recovered_ram, so a leftover is never saved as the new shot.
    private func drainRAM() async {
        _ = await ramEvents()
        var emptied = 0
        var seen: [RAMFile] = []
        for _ in 0..<8 {
            var parked = await ramInfo(PTP.sdramHandle)
            if parked == nil { parked = await ramInfo(PTP.sdramHandle2) }
            guard let info = parked else { break }
            if seen.contains(info) {
                await emptyRAM()
                break
            }
            seen.append(info)
            if let data = try? await readObject(info), data.count == Int(info.size) {
                writeRecovered(data, index: emptied)
                emptied += 1
            }
            await release(info)
        }
        if emptied > 0 { print("FXPAN \(model) cleared \(emptied) old RAM frame(s)") }
    }

    private func writeRecovered(_ data: Data, index: Int) {
        let ext = data.starts(with: [0xFF, 0xD8]) ? "jpg" : "nef"
        let dir = Disk.captures.appendingPathComponent("recovered_ram", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(model.filter { $0.isNumber })_\(index).\(ext)")
        try? data.write(to: url, options: .atomic)
    }

    func shoot(stamp: String, role: Role, photo: Photo) async throws -> Grabbed {
        try await ensureSession()
        await stopLive()
        try await aimRAM(photo)
        await drainRAM()
        await settle(minimum: 0.4, seconds: 4)
        var reply = try await transact(PTP.Op.captureSDRAM.rawValue, params: [0xFFFF_FFFF], timeout: 60)
        print("FXPAN \(model) captureRAM \(Self.hex(reply.code))")
        if reply.code == 0x2019 {
            await settle(minimum: 1.5, seconds: 12)
            reply = try await transact(PTP.Op.captureSDRAM.rawValue, params: [0xFFFF_FFFF], timeout: 60)
            print("FXPAN \(model) captureRAM2 \(Self.hex(reply.code))")
        }
        if !reply.ok {
            reply = try await transact(PTP.Op.initiateCapture.rawValue, params: [0, 0], timeout: 25)
            print("FXPAN \(model) capture \(Self.hex(reply.code))")
        }
        guard reply.ok else { throw PTPError.message("\(role.rawValue) did not fire \(Self.hex(reply.code))") }
        return try await takeRAM(stamp: stamp, role: role)
    }

    /// A JPEG starts with FF D8. Anything else from this slot is the NEF. The embedded preview fills in only when the body did not also send a JPEG.
    private func keep(_ data: Data, stamp: String, role: Role, jpegURL: inout URL?, nefURL: inout URL?) throws {
        if data.starts(with: [0xFF, 0xD8]) {
            let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).jpg")
            try data.write(to: url, options: .atomic)
            jpegURL = url
            return
        }
        let url = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).nef")
        try data.write(to: url, options: .atomic)
        nefURL = url
        let preview = Disk.captures.appendingPathComponent("\(role.rawValue)_\(stamp).jpg")
        if jpegURL == nil, !FileManager.default.fileExists(atPath: preview.path),
           let jpg = PTP.jpeg(in: data), jpg.count > 20_000 {
            try jpg.write(to: preview, options: .atomic)
            jpegURL = preview
        }
    }

    /// ImageCapture returned an empty buffer when one GetObject was the whole frame. GetPartialObject (0x101B: handle, offset, max bytes) in pieces comes through.
    /// The piece halves on an empty reply, and the size that worked carries over to the next file.
    private var pieceBytes: UInt32 = 8 << 20

    private func readObject(_ info: RAMFile) async throws -> Data {
        let started = CFAbsoluteTimeGetCurrent()
        var blob = Data()
        blob.reserveCapacity(Int(info.size))
        while blob.count < Int(info.size) {
            let offset = UInt32(blob.count)
            let ask = min(pieceBytes, info.size - offset)
            let part = try await transact(PTP.Op.getPartial.rawValue, params: [info.handle, offset, ask], timeout: 30, endSession: true)
            let bytes = Self.objectPayload(part.raw)
            if part.ok, !bytes.isEmpty {
                blob.append(bytes.prefix(Int(info.size) - blob.count))
                continue
            }
            if offset == 0, part.code == 0x2005 {
                return try await readWhole(info, started: started)
            }
            guard part.ok, pieceBytes > 128 << 10 else {
                print(String(format: "FXPAN %@ read %08X stopped @%u %@", model, info.handle, offset, Self.hex(part.code)))
                break
            }
            pieceBytes /= 2
            print("FXPAN \(model) read piece \(pieceBytes >> 10) KB")
        }
        let seconds = CFAbsoluteTimeGetCurrent() - started
        noteTransfer(bytes: blob.count, seconds: seconds)
        print(String(format: "FXPAN %@ read %08X %d bytes %.2fs piece %u KB", model, info.handle, blob.count, seconds, pieceBytes >> 10))
        return blob
    }

    /// GetObject (0x1009) for a body that does not support GetPartialObject.
    private func readWhole(_ info: RAMFile, started: CFAbsoluteTime) async throws -> Data {
        let file = try await transact(PTP.Op.getObject.rawValue, params: [info.handle], timeout: 90, endSession: true)
        guard file.ok else { return Data() }
        let bytes = Self.objectPayload(file.raw)
        noteTransfer(bytes: bytes.count, seconds: CFAbsoluteTimeGetCurrent() - started)
        return bytes
    }

    /// A real file must not be trimmed just because four bytes in the middle look like a PTP header.
    private static func objectPayload(_ raw: Data) -> Data {
        guard raw.count >= 12, raw.u16(4) == 2 else { return raw }
        let code = raw.u16(6)
        guard code == PTP.Op.getObject.rawValue || code == PTP.Op.getPartial.rawValue else { return raw }
        let declared = Int(raw.u32(0))
        guard declared >= 12, declared <= raw.count else { return raw }
        return raw.subdata(in: 12..<declared)
    }

    /// USB 2 cannot deliver 55 MB/s of payload. A short transfer is not long enough to call a slow link.
    private func noteTransfer(bytes: Int, seconds: Double) {
        guard bytes >= 1_000_000, seconds >= 0.05 else { return }
        let rate = Double(bytes) / seconds / 1_000_000
        let next: String
        if rate >= 55 {
            next = "USB3 · \(Int(rate.rounded())) MB/s"
        } else if seconds >= 0.4 {
            next = "USB2 · \(Int(rate.rounded())) MB/s"
        } else {
            return
        }
        linkLabel = next
        print("FXPAN \(model) \(linkLabel) \(bytes) bytes")
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

    /// A poll that runs long must not close the session. Closing it is what turns a busy body into "Camera did not answer" on the next read.
    /// A file transfer that stalls still closes the session, because that is the command the body is stuck inside.
    private var pollStalled = false

    private func transact(_ code: UInt16, params: [UInt32] = [], out: Data? = nil, timeout: Double = 8, endSession: Bool = false) async throws -> PTP.Reply {
        if pollStalled {
            pollStalled = false
            Trace.line("FXPAN \(model) reopening the session after a slow reply")
            await abortSession()
            try await ensureSession()
        }
        let transaction = txn
        txn &+= 1
        let command = PTP.command(code: code, transaction: transaction, params: params)
        return try await enqueue {
            try await self.roundTrip(command, out: out, timeout: timeout, endSession: endSession)
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
    /// ImageCapture does not retain the delegate. Keep it until the callback, including after a timeout.
    private var heldSinks: [PTPSink] = []

    private func roundTrip(_ command: Data, out: Data?, timeout: Double, endSession: Bool) async throws -> PTP.Reply {
        let device = self.device
        let sink = PTPSink()
        self.sink = sink
        heldSinks.append(sink)
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<PTP.Reply, Error>) in
            let gate = Gate()
            sink.finish = { [weak self] data, response, error in
                self?.heldSinks.removeAll { $0 === sink }
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
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard gate.claim() else { return }
                let op = command.count >= 8 ? String(format: "%04X", command.u16(6)) : "?"
                if endSession {
                    Trace.line("FXPAN \(self.model) ptp \(op) stalled, closing the session so the body can leave transfer")
                    await self.abortSession()
                } else {
                    Trace.line("FXPAN \(self.model) ptp \(op) slow, leaving the session up")
                    self.pollStalled = true
                }
                self.heldSinks.removeAll { $0 === sink }
                cont.resume(throwing: PTPError.timeout)
            }
        }
    }

    /// Drop the USB session. A body stuck sending a file only returns to idle when this command is abandoned, not when another opcode is stacked on top.
    private func abortSession() async {
        sessionUp = false
        inLive = false
        guard device.hasOpenSession else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            device.requestCloseSession(options: nil) { _ in cont.resume() }
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

    private struct PTPEvent {
        var code: UInt16
        var param: UInt32
    }

    private static func events(_ data: Data) -> [PTPEvent] {
        guard data.count >= 2 else { return [] }
        let count = min(Int(data.u16(0)), 32)
        var i = 2
        var out: [PTPEvent] = []
        for _ in 0..<count {
            if i + 6 > data.count { break }
            let code = data.u16(i)
            let param = data.u32(i + 2)
            out.append(PTPEvent(code: code, param: param))
            i += 6
        }
        return out
    }

    private static func eventBrief(_ data: Data) -> String {
        guard data.count >= 2 else { return "empty" }
        let count = min(Int(data.u16(0)), 8)
        var i = 2
        var parts: [String] = []
        for _ in 0..<count {
            if i + 6 > data.count { break }
            parts.append(String(format: "%04X:%08X", data.u16(i), data.u32(i + 2)))
            i += 6
        }
        return parts.joined(separator: " ")
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
