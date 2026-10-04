import UIKit
import SwiftUI

enum Route: Hashable {
    case home
    case frame, light, focus, look, drive, wb
    case modes
    case playback
    case shot(String)
    case system, cameras, rig, display, storage, about, apple
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
    var idleMinutes = 5
    var idleChosen = false
    /// Nil until the Apple panel is touched. Nil offers every Core Image effect.
    var appleOn: [String]?
    /// GPU bilinear for the full-resolution warp. Off uses the same sample on the CPU.
    var metalWarp = true
    var sleeping = false
    var toast: Toast?
    var countdown: Int?
    var shooting = false
    var syncReady = false
    var stitchLabel: String?
    var stitchingStamp: String?
    /// Bumped when a stitch finishes so an open photo reloads the new file.
    var stitchGeneration = 0
    var stitchWaiting: Set<String> = []
    var savingStyle: String?
    var upscaleLabel: String?
    var reviewStamp: String?
    var peepURL: URL?
    var peepTitle = ""
    var messages: [String] = []
    var preview: UIImage?
    var rangeT: FocusAim = .lost
    var rangeR: FocusAim = .lost
    /// A tap on the panorama, in unit coordinates. Nil follows the sharpest part of the stitch.
    var focusAt: CGPoint?
    var focusBox: CGRect?
    var focusSharp: CGRect?
    var focusPlace: FocusPlace = .both
    var playingFocus = false
    var simulate = false
    /// Bumped whenever a camera connects, pairs, or changes live view, so the shutter and pills redraw.
    var cameraRevision = 0
    /// Bumped when a body is added, removed, or reseated. Settings pages use this, not every live frame.
    var usbRevision = 0

    let camera = CameraHub()
    private let dialT = FocusDial()
    private let dialR = FocusDial()
    private var lastPlace: FocusPlace?
    /// Sharpest the current focus window has been. Kept so a blur cannot drag the box onto a different edge.
    private var heldBest = 0.0
    private var applyTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var reviewTask: Task<Void, Never>?
    private var stitchQueue: [String] = []
    private var stitchRunning = false
    private var stitchHold: UIBackgroundTaskIdentifier = .invalid
    private var stitchPhase = "Stitching"
    private var stitchBegan = Date()
    private var stitchClock: Task<Void, Never>?
    private var stitchPiece: Task<StitchReport, Error>?
    private let stitchStop = StitchStopFlag()
    private var scenePhase: ScenePhase = .active
    private var previewToken = 0

    var activeMode: NamedMode? { modes.first { $0.id == activeModeID } }
    var modeDrifted: Bool {
        guard let mode = activeMode else { return false }
        return mode.photo != photo
    }

    func start() async {
        var state = Disk.load()
        photo = state.photo
        let huginMark = Disk.support.appendingPathComponent("hugin-default")
        let adoptHugin = !FileManager.default.fileExists(atPath: huginMark.path)
        if adoptHugin && photo.drive.engine == "match" { photo.drive.engine = "hugin" }
        modes = state.modes
        let addApple = !modes.contains { $0.id == "apple" }
        if addApple { modes.insert(Seed.appleMode(), at: 0) }
        activeModeID = state.activeModeID
        rig = state.rig
        notes = state.shots
        protectedStamps = Set(state.protectedStamps)
        idleMinutes = state.idleChosen ? state.idleMinutes : 5
        idleChosen = state.idleChosen
        appleOn = state.appleOn
        metalWarp = state.metalWarp ?? true
        simulate = state.simulate
        if adoptHugin {
            try? Data("1".utf8).write(to: huginMark)
        }
        if addApple || (adoptHugin && photo.drive.engine == "hugin") { persist() }
        camera.simulate = state.simulate
        camera.onChange = { [weak self] in
            self?.cameraRevision += 1
            self?.ingest()
        }
        camera.onSeat = { [weak self] in
            self?.usbRevision += 1
        }
        camera.onReady = { [weak self] in
            guard let self, !self.shooting else { return }
            self.scheduleApply()
        }
        #if targetEnvironment(simulator)
        SampleShots.install()
        #endif
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
        if await SyncLink.ping() {
            syncReady = true
            if photo.drive.release != "sync" {
                photo.drive.release = "sync"
                persist()
            }
            note("10-pin sync on", bad: false)
        }
        ingest()
        armIdle()
        watchSync()
        if ProcessInfo.processInfo.arguments.contains("-shootSim") {
            photo.drive.review = 0
            try? await Task.sleep(nanoseconds: 600_000_000)
            await fire()
        }
    }

    /// A stitch keeps running for the short time iOS allows after a switch away. This is not a background-processing mode. The hold exists only while the app is actually in the background and a stitch is in flight.
    func scene(_ phase: ScenePhase) async {
        scenePhase = phase
        switch phase {
        case .active:
            endStitchHold()
            if idleDue, idleMinutes > 0 {
                await idleDown()
            } else if !sleeping {
                await camera.foreground()
            }
        case .background:
            camera.background()
            if stitchRunning { beginStitchHold() }
            if idleDue, idleMinutes > 0 { await idleDown() }
        default:
            break
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
        idleChosen = true
        idleMinutes = minutes
        applyIdle()
        persist()
        if minutes == 0, sleeping {
            sleeping = false
            Task { await camera.wakeFromIdle() }
        }
        armIdle()
    }

    /// A touch. Restarts the sleep clock, and brings the bodies back if they had been released.
    func poke() {
        let now = Date()
        if sleeping {
            sleeping = false
            lastPoke = now
            Task { await camera.wakeFromIdle() }
            armIdle()
            return
        }
        if now.timeIntervalSince(lastPoke) < 1 { return }
        lastPoke = now
        armIdle()
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

    func probeSync() async {
        if shooting { return }
        syncReady = await SyncLink.ping()
    }

    /// Keeps the top-bar Sync mark current. A ping during a release would sit on the same socket as FIRE.
    private func watchSync() {
        syncWatch?.cancel()
        syncWatch = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.photo.drive.release == "sync" {
                    await self.probeSync()
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func toggleLive() async {
        await camera.setLive(!camera.live)
        ingest()
    }

    /// Pin the rangefinder on a point in the panorama. Tapping the current window lets it follow the sharp part again.
    func aimFocus(_ point: CGPoint) {
        let p = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
        if let focusAt, FocusMeter.window(around: focusAt).contains(p) {
            self.focusAt = nil
        } else {
            focusAt = p
        }
        dialT.reset()
        dialR.reset()
        lastPlace = nil
        heldBest = 0
        focusBox = nil
        schedulePreview()
    }

    /// Walk each captured panorama from sharp to soft and back, so the box and the arrow can be reviewed on a real picture.
    func playFocus() async {
        guard camera.simulate, !playingFocus else { return }
        let pages = focusPages()
        guard !pages.isEmpty else {
            note("No captured panorama to play", bad: true)
            return
        }
        playingFocus = true
        camera.focusHold = true
        camera.focusDrive = true
        defer {
            playingFocus = false
            camera.focusBlur = 0
            camera.focusHold = false
            camera.focusDrive = false
            ingest()
        }
        if !camera.live {
            await camera.setLive(true)
        }
        let steps = Self.blurSteps()
        let aim = focusAt
        for page in pages {
            dialT.reset()
            dialR.reset()
            lastPlace = nil
            focusBox = nil
            heldBest = 0
            let source = page.image
            let fitted = await Task.detached(priority: .userInitiated) {
                Self.fitPlay(source)
            }.value
            let overlap = page.overlap
            for radius in steps {
                let frame = await Task.detached(priority: .userInitiated) {
                    FrameBlur.image(fitted, radius: radius)
                }.value
                let hold = aim == nil ? self.focusBox : nil
                let best = self.heldBest
                let read = await Task.detached(priority: .userInitiated) {
                    FocusMeter.read(frame, aim: aim, overlap: overlap, only: nil, hold: hold, holdBest: best)
                }.value
                preview = UIImage(cgImage: frame)
                applyFocus(read)
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
        }
    }

    private struct FocusPage {
        var image: CGImage
        var overlap: Double
    }

    private struct PanoOverlap: Decodable {
        var overlap: Double?
    }

    /// Captured stitches in the library, newest first. The overlap written beside each file places R and T.
    private func focusPages() -> [FocusPage] {
        shots.compactMap(\.pano).compactMap { url in
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
            let overlap = storedOverlap(beside: url) ?? rig.overlap
            return FocusPage(image: image, overlap: overlap)
        }
    }

    private func applyFocus(_ read: FocusRead) {
        if read.place != lastPlace {
            dialT.reset()
            dialR.reset()
            lastPlace = read.place
        }
        switch read.place {
        case .t:
            rangeT = read.score.map { dialT.push($0) } ?? .lost
            rangeR = .lost
        case .r:
            rangeR = read.score.map { dialR.push($0) } ?? .lost
            rangeT = .lost
        case .both:
            if let score = read.score {
                rangeT = dialT.push(score)
                rangeR = dialR.push(score)
            } else {
                rangeT = .lost
                rangeR = .lost
            }
        }
        focusBox = read.box
        focusSharp = read.box
        focusPlace = read.place
        heldBest = read.holdBest
    }

    private func clearFocus() {
        dialT.reset()
        dialR.reset()
        lastPlace = nil
        rangeT = .lost
        rangeR = .lost
        focusBox = nil
        focusSharp = nil
        heldBest = 0
    }

    private static func blurSteps() -> [CGFloat] {
        var steps: [CGFloat] = []
        var radius: CGFloat = 0
        while radius < 30 {
            steps.append(radius)
            radius += 3
        }
        while radius > 0 {
            steps.append(radius)
            radius -= 3
        }
        steps.append(0)
        return steps
    }

    nonisolated private static func fitPlay(_ image: CGImage) -> CGImage {
        let maxW = 1400
        guard image.width > maxW else { return image }
        let height = max(16, Int((Double(image.height) * Double(maxW) / Double(image.width)).rounded()))
        return Stitcher.sized(image, to: maxW, height: height)
    }

    private func storedOverlap(beside jpeg: URL) -> Double? {
        let json = jpeg.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: json),
              let note = try? JSONDecoder().decode(PanoOverlap.self, from: data),
              let overlap = note.overlap, overlap > 0.05, overlap < 0.55 else { return nil }
        return overlap
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
        reviewTask?.cancel()
        droppedStamps.insert(stamp)
        stitchQueue.removeAll { $0 == stamp }
        stitchWaiting.remove(stamp)
        if stitchingStamp == stamp {
            stitchStop.cancel()
            stitchPiece?.cancel()
        }
        CaptureIndex.delete(stamp: stamp)
        notes[stamp] = nil
        if reviewStamp == stamp { reviewStamp = nil }
        persist()
        reloadShots()
        ingest()
    }

    /// The stitcher may already be holding this pair. Drop the result instead of writing it back.
    private func discard(_ stamp: String) -> Bool {
        guard droppedStamps.contains(stamp) else { return false }
        droppedStamps.remove(stamp)
        CaptureIndex.delete(stamp: stamp)
        stitchStop.reset()
        reloadShots()
        return true
    }

    var appleEnabled: [String] { appleOn ?? AppleBook.defaultOn }

    func setApple(_ id: String, on: Bool) {
        var ids = appleEnabled
        if on {
            if !ids.contains(id) { ids.append(id) }
        } else {
            ids.removeAll { $0 == id }
        }
        appleOn = AppleBook.effects.map(\.id).filter { ids.contains($0) }
        persist()
    }

    func setMetalWarp(_ on: Bool) {
        metalWarp = on
        persist()
    }

    /// Remember which Apple effect the viewer is trying. The file changes only on Save look.
    func stageApple(_ stamp: String, _ apple: String) {
        var row = notes[stamp] ?? ShotNote()
        row.styleApple = apple
        notes[stamp] = row
        persist()
    }

    func protect(_ stamp: String) {
        if protectedStamps.contains(stamp) { protectedStamps.remove(stamp) }
        else { protectedStamps.insert(stamp) }
        persist()
    }

    /// Real-ESRGAN on the panorama. Subject tiles use the network. A later tap reads the saved original, so the enlarge does not stack.
    func upscale(_ stamp: String) {
        if upscaleLabel != nil || savingStyle != nil { return }
        let pano = Disk.captures.appendingPathComponent("P_\(stamp).jpg")
        guard FileManager.default.fileExists(atPath: pano.path) else {
            note("No panorama to upscale", bad: true)
            return
        }
        upscaleLabel = "Upscaling"
        note("Upscaling", bad: false)
        let ana = Disk.captures.appendingPathComponent("P_\(stamp)_ana.jpg")
        let squeeze = notes[stamp]?.squeeze ?? photo.frame.squeeze
        let hasAna = FileManager.default.fileExists(atPath: ana.path)
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let source = try UpscaleStore.source(stamp: stamp, pano: pano)
                guard let cg = Stitcher.image(at: source) else {
                    throw PTPError.message("Could not read the panorama")
                }
                let (out, scale) = try SuperRes.image(cg) { phase in
                    Task { @MainActor in self?.upscaleLabel = phase }
                }
                let dir = Disk.captures.appendingPathComponent("upscale", isDirectory: true)
                let tmp = dir.appendingPathComponent("writing-\(stamp).jpg")
                try Stitcher.jpeg(out, to: tmp)
                _ = try FileManager.default.replaceItemAt(pano, withItemAt: tmp)
                if hasAna, squeeze > 1.01 {
                    let wideW = Int((Double(out.width) * squeeze).rounded())
                    if wideW > out.width, Int64(wideW) * Int64(out.height) * 4 < 1_600_000_000 {
                        let wide = Stitcher.stretch(out, squeeze: squeeze)
                        if wide.width == wideW {
                            try Stitcher.jpeg(wide, to: ana)
                        }
                    }
                }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.upscaleLabel = nil
                    self.stitchGeneration += 1
                    self.reloadShots()
                    self.note("Upscaled \(scale)×", bad: false)
                    self.ingest()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.upscaleLabel = nil
                    self.note(error.localizedDescription, bad: true)
                }
            }
        }
    }

    /// Write the playback style onto the panorama. The unstyled stitch is kept, so another save replaces it.
    func saveStyle(_ stamp: String, look: LookSet) {
        if savingStyle != nil { return }
        let pano = Disk.captures.appendingPathComponent("P_\(stamp).jpg")
        guard FileManager.default.fileExists(atPath: pano.path) else {
            note("No panorama to save", bad: true)
            return
        }
        savingStyle = stamp
        note("Saving the look", bad: false)
        let ana = Disk.captures.appendingPathComponent("P_\(stamp)_ana.jpg")
        let look = look
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try LookStore.keep(stamp: stamp, look: look, pano: pano, ana: ana)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    var row = self.notes[stamp] ?? ShotNote()
                    row.look = LookBook.savedTitle(look)
                    row.styleBase = look.base
                    row.styleGrain = look.grain
                    row.styleFilter = look.filter
                    row.styleApple = look.apple
                    self.notes[stamp] = row
                    self.savingStyle = nil
                    self.stitchGeneration += 1
                    self.persist()
                    self.reloadShots()
                    self.note("Saved \(row.look)", bad: false)
                    self.ingest()
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.savingStyle = nil
                    self.note(error.localizedDescription, bad: true)
                    self.ingest()
                }
            }
        }
    }

    func restitch(_ stamp: String, engine: String? = nil) {
        if let engine, photo.drive.engine != engine {
            photo.drive.engine = engine
            persist()
        }
        if stitchingStamp == stamp {
            restartStamp = stamp
            stitchStop.cancel()
            stitchPiece?.cancel()
        }
        stitchQueue.removeAll { $0 == stamp }
        enqueue(stamp)
    }

    /// The stitch in flight was stopped so this set can run again with another engine.
    private func tookRestart(_ stamp: String) -> Bool {
        guard restartStamp == stamp else { return false }
        restartStamp = nil
        stitchStop.reset()
        return true
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
                if self.playingFocus { continue }
                let t = self.camera.frames[.t]?.cgImage
                let r = self.camera.frames[.r]?.cgImage
                let meter = self.camera.live && photo.focus.aid != "off"
                let aim = self.focusAt
                let hold = aim == nil ? self.focusBox : nil
                let best = self.heldBest
                let made = await Task.detached(priority: .userInitiated) {
                    Self.makePreview(t: t, r: r, rig: rig, photo: photo, fallback: panoURL, meter: meter, aim: aim, hold: hold, holdBest: best)
                }.value
                if self.playingFocus { continue }
                if let image = made.image {
                    self.preview = image
                }
                if meter {
                    self.applyFocus(FocusRead(score: made.score, box: made.box, sharp: made.box, place: made.place, holdBest: made.holdBest))
                } else {
                    self.clearFocus()
                }
            }
            self.previewBusy = false
            if self.previewDirty { self.schedulePreview() }
        }
    }

    private struct PreviewMade {
        var image: UIImage?
        var score: Double?
        var box: CGRect?
        var sharp: CGRect?
        var place: FocusPlace = .both
        var holdBest: Double = 0
    }

    nonisolated private static func makePreview(t: CGImage?, r: CGImage?, rig: Rig, photo: Photo, fallback: URL?, meter: Bool, aim: CGPoint?, hold: CGRect?, holdBest: Double) -> PreviewMade {
        if let t, let r, let cg = Stitcher.preview(t: t, r: r, rig: rig, squeeze: photo.frame.squeeze, maxWidth: 1400) {
            let read = meter ? FocusMeter.read(cg, aim: aim, overlap: rig.overlap(width: t.width, height: t.height), only: nil, hold: hold, holdBest: holdBest) : FocusRead()
            var out = cg
            if !LookBook.identity(photo.look) { out = Stitcher.grade(out, look: photo.look) }
            if photo.focus.aid == "peaking" { out = Peak.draw(out, color: photo.focus.color, level: photo.focus.level) }
            return PreviewMade(image: UIImage(cgImage: out), score: read.score, box: read.box, sharp: read.sharp, place: read.place, holdBest: read.holdBest)
        }
        if let t {
            let read = meter ? FocusMeter.read(t, aim: aim, overlap: rig.overlap, only: .t, hold: hold, holdBest: holdBest) : FocusRead(place: .t)
            return PreviewMade(image: UIImage(cgImage: t), score: read.score, box: read.box, sharp: read.sharp, place: read.place, holdBest: read.holdBest)
        }
        if let r {
            let read = meter ? FocusMeter.read(r, aim: aim, overlap: rig.overlap, only: .r, hold: hold, holdBest: holdBest) : FocusRead(place: .r)
            return PreviewMade(image: UIImage(cgImage: r), score: read.score, box: read.box, sharp: read.sharp, place: read.place, holdBest: read.holdBest)
        }
        if let fallback, let image = UIImage(contentsOfFile: fallback.path) {
            return PreviewMade(image: image)
        }
        return PreviewMade()
    }

    private func scheduleApply() {
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard let self, !Task.isCancelled, !self.shooting else { return }
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
        stitchLabel = stitchRunning ? "Queued · \(stitchQueue.count)" : "Reading the pair"
        if !stitchRunning {
            stitchStop.reset()
            stitchRunning = true
            if scenePhase == .background { beginStitchHold() }
            Task { await drain() }
        }
    }

    func cancelStitch() {
        guard stitchRunning else { return }
        stitchQueue.removeAll()
        stitchWaiting = []
        stitchStop.cancel()
        stitchPiece?.cancel()
        noteStitch("Cancelling")
    }

    func peep(_ url: URL?, title: String) {
        guard let url else { return }
        peepTitle = title
        peepURL = url
    }

    func closePeep() {
        peepURL = nil
    }

    /// Asked only while the app is in the background and a stitch is still running. Ended as soon as the app is visible again, or when the queue is empty.
    private func beginStitchHold() {
        guard stitchRunning, stitchHold == .invalid else { return }
        stitchHold = UIApplication.shared.beginBackgroundTask(withName: "fxpan-stitch") { [weak self] in
            Task { @MainActor in self?.endStitchHold() }
        }
    }

    private func endStitchHold() {
        let id = stitchHold
        guard id != .invalid else { return }
        stitchHold = .invalid
        UIApplication.shared.endBackgroundTask(id)
    }

    func noteStitch(_ phase: String) {
        stitchPhase = phase
        paintStitch()
    }

    private func beginClock() {
        stitchBegan = Date()
        stitchPhase = "Reading the pair"
        paintStitch()
        stitchClock?.cancel()
        stitchClock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                self?.paintStitch()
            }
        }
    }

    private func paintStitch() {
        let elapsed = max(0, Int(Date().timeIntervalSince(stitchBegan)))
        let clock = elapsed < 60 ? "\(elapsed)s" : "\(elapsed / 60)m \(elapsed % 60)s"
        let waiting = stitchQueue.count
        stitchLabel = waiting == 0 ? "\(stitchPhase) · \(clock)" : "\(stitchPhase) · \(clock) · \(waiting) waiting"
    }

    private func drain() async {
        defer {
            stitchRunning = false
            stitchLabel = nil
            stitchingStamp = nil
            stitchWaiting = []
            stitchClock?.cancel()
            stitchClock = nil
            endStitchHold()
            reloadShots()
            ingest()
        }
        while !stitchQueue.isEmpty {
            let stamp = stitchQueue.removeFirst()
            stitchingStamp = stamp
            var waiting = stitchWaiting
            waiting.remove(stamp)
            stitchWaiting = waiting
            beginClock()
            await runStitch(stamp)
            reloadShots()
        }
    }

    private func runStitch(_ stamp: String) async {
        if discard(stamp) { return }
        let shot = CaptureIndex.list().first { $0.stamp == stamp }
        guard let t = shot?.t, let r = shot?.r else {
            if discard(stamp) { return }
            note("Need T and R for \(stamp)", bad: true)
            return
        }
        let dest = Disk.captures.appendingPathComponent("P_\(stamp).jpg")
        let ana = photo.frame.squeeze > 1.01 ? Disk.captures.appendingPathComponent("P_\(stamp)_ana.jpg") : nil
        let rig = rig
        let photo = photo
        do {
            let note: StitchNote = { phase in
                Task { @MainActor in self.noteStitch(phase) }
            }
            let stop = stitchStop
            let metal = metalWarp
            let job = Task.detached(priority: .userInitiated) {
                try Stitcher.write(tURL: t, rURL: r, dest: dest, ana: ana, rig: rig, photo: photo, metal: metal, note: note, stop: { stop.cancelled })
            }
            stitchPiece = job
            defer { stitchPiece = nil }
            let started = CFAbsoluteTimeGetCurrent()
            var report = try await job.value
            if discard(stamp) { return }
            if tookRestart(stamp) { return }
            if stitchStop.cancelled { throw StitchHalt() }
            report.sec = CFAbsoluteTimeGetCurrent() - started
            let side = Disk.captures.appendingPathComponent("P_\(stamp).json")
            if let data = try? JSONEncoder().encode(report) {
                try? data.write(to: side)
            }
            LookStore.remove(stamp)
        } catch is StitchHalt {
            if discard(stamp) { return }
            if tookRestart(stamp) { return }
            note("Stitch cancelled", bad: false)
        } catch is CancellationError {
            if discard(stamp) { return }
            if tookRestart(stamp) { return }
            note("Stitch cancelled", bad: false)
        } catch {
            if discard(stamp) { return }
            if tookRestart(stamp) { return }
            note(error.localizedDescription, bad: true)
        }
        stitchGeneration += 1
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
        state.idleChosen = idleChosen
        state.appleOn = appleOn
        state.metalWarp = metalWarp
        Disk.save(state)
    }

    private var idleTask: Task<Void, Never>?
    private var syncWatch: Task<Void, Never>?
    private var droppedStamps: Set<String> = []
    private var restartStamp: String?
    private var idleDeadline: Date?
    private var lastPoke = Date.distantPast

    private var idleDue: Bool {
        guard let idleDeadline else { return false }
        return Date() >= idleDeadline
    }

    private func armIdle() {
        idleTask?.cancel()
        idleTask = nil
        guard idleMinutes > 0, !sleeping else {
            idleDeadline = nil
            return
        }
        let deadline = Date().addingTimeInterval(TimeInterval(idleMinutes * 60))
        idleDeadline = deadline
        idleTask = Task { [weak self] in
            let wait = deadline.timeIntervalSinceNow
            if wait > 0 {
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            await self.idleDown()
        }
    }

    private func idleDown() async {
        if shooting {
            armIdle()
            return
        }
        guard !sleeping else { return }
        sleeping = true
        idleTask?.cancel()
        idleTask = nil
        await camera.idleDown()
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

final class StitchStopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func cancel() {
        lock.lock()
        value = true
        lock.unlock()
    }

    func reset() {
        lock.lock()
        value = false
        lock.unlock()
    }

    var cancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
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
