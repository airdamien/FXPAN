import UIKit

enum Route: Hashable {
    case home
    case frame, light, focus, look, drive, wb
    case modes
    case playback
    case shot(String)
    case system, cameras, rig, display, storage, about
}

struct Toast: Equatable {
    var text: String
    var bad: Bool
}

@MainActor
@Observable
final class AppModel {
    var route: [Route] = []
    var photo = Photo()
    var modes: [NamedMode] = []
    var activeModeID: String?
    var rig = Rig()
    var shots: [ShotFiles] = []
    var notes: [String: ShotNote] = [:]
    var protectedStamps: Set<String> = []
    var idleMinutes = 0
    var toast: Toast?
    var countdown: Int?
    var shooting = false
    var stitchLabel: String?
    var stitchingStamp: String?
    var stitchWaiting: Set<String> = []
    var reviewStamp: String?
    var messages: [String] = []
    var preview: UIImage?
    var simulate = false
    /// Bumped whenever a camera connects, pairs, or changes live view, so the shutter and pills redraw.
    var cameraRevision = 0

    let camera = CameraHub()
    private var applyTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var stitchQueue: [String] = []
    private var stitchRunning = false
    private var previewToken = 0

    var activeMode: NamedMode? { modes.first { $0.id == activeModeID } }
    var modeDrifted: Bool {
        guard let mode = activeMode else { return false }
        return mode.photo != photo
    }

    func start() async {
        var state = Disk.load()
        photo = state.photo
        modes = state.modes
        activeModeID = state.activeModeID
        rig = state.rig
        notes = state.shots
        protectedStamps = Set(state.protectedStamps)
        idleMinutes = state.idleMinutes
        simulate = state.simulate
        camera.simulate = state.simulate
        camera.onChange = { [weak self] in
            self?.cameraRevision += 1
            self?.ingest()
        }
        if let renamed = CaptureIndex.renameLegacy(stamp: "probe") {
            if let note = notes.removeValue(forKey: "probe") { notes[renamed] = note }
            if protectedStamps.remove("probe") != nil { protectedStamps.insert(renamed) }
            persist()
        }
        reloadShots()
        let marker = Disk.support.appendingPathComponent("orient-upright")
        let redo = !FileManager.default.fileExists(atPath: marker.path)
        for shot in shots where shot.ready && (redo || shot.pano == nil) {
            enqueue(shot.stamp)
        }
        if redo { try? Data("1".utf8).write(to: marker) }
        applyIdle()
        await camera.start()
        ingest()
        if ProcessInfo.processInfo.arguments.contains("-shootSim") {
            photo.drive.review = 0
            try? await Task.sleep(nanoseconds: 600_000_000)
            await fire()
        }
    }

    func go(_ next: Route) { route.append(next) }
    func home() { route.removeAll() }
    func back() { if !route.isEmpty { route.removeLast() } }

    func edit(_ body: (inout Photo) -> Void) {
        body(&photo)
        persist()
        scheduleApply()
        ingest()
    }

    func editRig(_ body: (inout Rig) -> Void) {
        body(&rig)
        persist()
        ingest()
    }

    func setSimulate(_ on: Bool) {
        simulate = on
        camera.simulate = on
        persist()
        ingest()
    }

    func setIdle(_ minutes: Int) {
        idleMinutes = minutes
        applyIdle()
        persist()
    }

    func recall(_ mode: NamedMode) async {
        photo = mode.photo
        activeModeID = mode.id
        persist()
        await camera.apply(photo)
        ingest()
        home()
        note("\(mode.name) recalled", bad: false)
    }

    func saveMode(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = UUID().uuidString
        modes.insert(NamedMode(id: id, name: trimmed, photo: photo), at: 0)
        activeModeID = id
        persist()
        note("Created \(trimmed)", bad: false)
    }

    func deleteMode(_ id: String) {
        modes.removeAll { $0.id == id }
        if activeModeID == id { activeModeID = nil }
        persist()
    }

    func toggleLive() async {
        await camera.setLive(!camera.live)
        ingest()
    }

    func fire() async {
        if shooting { return }
        shooting = true
        ingest()
        let wait = photo.drive.timer
        if wait > 0 {
            for s in stride(from: wait, through: 1, by: -1) {
                countdown = s
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdown = nil
        }
        let stamp = CaptureIndex.stampNow()
        do {
            let grabbed = try await camera.capture(stamp: stamp, photo: photo)
            notes[stamp] = ShotNote(modeName: activeMode?.name ?? "", look: LookBook.name(photo.look), squeeze: photo.frame.squeeze)
            persist()
            reloadShots()
            if photo.drive.autoStitch, grabbed[.t]?.jpeg != nil, grabbed[.r]?.jpeg != nil {
                enqueue(stamp)
            } else if let url = grabbed[.t]?.jpeg ?? grabbed[.r]?.jpeg, let image = UIImage(contentsOfFile: url.path) {
                preview = image
            }
            if photo.drive.review > 0 {
                reviewStamp = stamp
                reviewTask?.cancel()
                reviewTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(self?.photo.drive.review ?? 0) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    self?.reviewStamp = nil
                }
            }
            note("\(stamp)", bad: false)
        } catch {
            note(error.localizedDescription, bad: true)
        }
        shooting = false
        countdown = nil
        ingest()
    }

    func deleteShot(_ stamp: String) {
        guard !protectedStamps.contains(stamp) else {
            note("Protected", bad: true)
            return
        }
        CaptureIndex.delete(stamp: stamp)
        notes[stamp] = nil
        if reviewStamp == stamp { reviewStamp = nil }
        persist()
        reloadShots()
        ingest()
    }

    func protect(_ stamp: String) {
        if protectedStamps.contains(stamp) { protectedStamps.remove(stamp) }
        else { protectedStamps.insert(stamp) }
        persist()
    }

    func restitch(_ stamp: String) {
        enqueue(stamp)
    }

    func pair(_ serial: String, role: Role) { camera.pair(serial, role: role) }
    func clearPair(_ role: Role) { camera.clear(role) }
    func swap() { camera.swap() }

    func setsLeft() -> Int? {
        guard let free = Disk.freeBytes() else { return nil }
        let each: Int64 = photo.drive.quality.contains("NEF") ? 40_000_000 : 12_000_000
        return Int(free / (each * 2))
    }

    // MARK: - Private

    private func ingest() {
        schedulePreview()
    }

    private var previewBusy = false
    private var previewDirty = false

    private func schedulePreview() {
        previewDirty = true
        guard !previewBusy else { return }
        previewBusy = true
        let rig = rig
        let photo = photo
        let panoURL = shots.first { $0.pano != nil }?.pano
        Task { [weak self] in
            guard let self else { return }
            while self.previewDirty {
                self.previewDirty = false
                let t = self.camera.frames[.t]?.cgImage
                let r = self.camera.frames[.r]?.cgImage
                let image = await Task.detached(priority: .userInitiated) {
                    await Self.makePreview(t: t, r: r, rig: rig, photo: photo, fallback: panoURL)
                }.value
                if let image {
                    self.preview = image
                }
            }
            self.previewBusy = false
            if self.previewDirty { self.schedulePreview() }
        }
    }

    private static func makePreview(t: CGImage?, r: CGImage?, rig: Rig, photo: Photo, fallback: URL?) async -> UIImage? {
        if let t, let r, let cg = Stitcher.preview(t: t, r: r, rig: rig, squeeze: photo.frame.squeeze, maxWidth: 1400) {
            var out = cg
            if !LookBook.identity(photo.look) { out = Stitcher.grade(out, look: photo.look) }
            if photo.focus.aid == "peaking" { out = Peak.draw(out, color: photo.focus.color, level: photo.focus.level) }
            return UIImage(cgImage: out)
        }
        if let t { return UIImage(cgImage: t) }
        if let r { return UIImage(cgImage: r) }
        if let fallback, let image = UIImage(contentsOfFile: fallback.path) { return image }
        return nil
    }

    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.camera.apply(self.photo)
            self.ingest()
        }
    }

    private func enqueue(_ stamp: String) {
        guard !stitchQueue.contains(stamp) else { return }
        stitchQueue.append(stamp)
        var waiting = stitchWaiting
        waiting.insert(stamp)
        stitchWaiting = waiting
        stitchLabel = stitchRunning ? "Queued · \(stitchQueue.count)" : "Stitching"
        if !stitchRunning {
            stitchRunning = true
            Task { await drain() }
        }
    }

    private func drain() async {
        defer {
            stitchRunning = false
            stitchLabel = nil
            stitchingStamp = nil
            stitchWaiting = []
            reloadShots()
            ingest()
        }
        while !stitchQueue.isEmpty {
            let stamp = stitchQueue.removeFirst()
            stitchingStamp = stamp
            var waiting = stitchWaiting
            waiting.remove(stamp)
            stitchWaiting = waiting
            stitchLabel = stitchQueue.isEmpty ? "Stitching" : "Stitching · \(stitchQueue.count) waiting"
            await runStitch(stamp)
            reloadShots()
        }
    }

    private func runStitch(_ stamp: String) async {
        let shot = CaptureIndex.list().first { $0.stamp == stamp }
        guard let t = shot?.t, let r = shot?.r else {
            note("Need T and R for \(stamp)", bad: true)
            return
        }
        let dest = Disk.captures.appendingPathComponent("P_\(stamp).jpg")
        let ana = photo.frame.squeeze > 1.01 ? Disk.captures.appendingPathComponent("P_\(stamp)_ana.jpg") : nil
        let rig = rig
        let photo = photo
        do {
            let report = try await Task.detached(priority: .userInitiated) {
                try Stitcher.write(tURL: t, rURL: r, dest: dest, ana: ana, rig: rig, photo: photo)
            }.value
            let side = Disk.captures.appendingPathComponent("P_\(stamp).json")
            if let data = try? JSONEncoder().encode(report) {
                try? data.write(to: side)
            }
        } catch {
            note(error.localizedDescription, bad: true)
        }
    }

    private func reloadShots() {
        shots = CaptureIndex.list()
    }

    private func persist() {
        var state = Persisted()
        state.photo = photo
        state.modes = modes
        state.activeModeID = activeModeID
        state.rig = rig
        state.simulate = simulate
        state.shots = notes
        state.protectedStamps = Array(protectedStamps)
        state.idleMinutes = idleMinutes
        Disk.save(state)
    }

    private func applyIdle() {
        UIApplication.shared.isIdleTimerDisabled = idleMinutes == 0
    }

    private func note(_ text: String, bad: Bool) {
        messages.insert(text, at: 0)
        if messages.count > 40 { messages.removeLast() }
        toast = Toast(text: text, bad: bad)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}

enum Peak {
    static func draw(_ image: CGImage, color: String, level: String) -> CGImage {
        let src = Stitcher.bitmap(image)
        let thresh = level == "high" ? 12 : (level == "low" ? 40 : 24)
        let rgb = Catalog.peakColors.first { $0.0 == color }?.2 ?? 0xFF3B30
        let cr = UInt8((rgb >> 16) & 0xFF)
        let cg = UInt8((rgb >> 8) & 0xFF)
        let cb = UInt8(rgb & 0xFF)
        var px = src.px
        func luma(_ i: Int) -> Int {
            Int(src.px[i]) * 3 + Int(src.px[i + 1]) * 6 + Int(src.px[i + 2])
        }
        let w = src.w, h = src.h
        if w < 3 || h < 3 { return image }
        for y in 1..<(h - 1) {
            for x in stride(from: 1, to: w - 1, by: 2) {
                let i = (y * w + x) * 4
                let mag = abs(luma(i) - luma(i - 4)) + abs(luma(i) - luma(i - w * 4))
                if mag > thresh * 30 {
                    px[i] = cr
                    px[i + 1] = cg
                    px[i + 2] = cb
                }
            }
        }
        return Stitcher.Bitmap(w: w, h: h, px: px).image()
    }
}
