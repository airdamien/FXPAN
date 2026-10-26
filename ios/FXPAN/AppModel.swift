import UIKit
import SwiftUI

enum Route: Hashable {
    case home
    case frame, light, focus, look, drive, wb, meter
    case modes
    case playback
    case shot(String)
    case raw(String)
    case system, cameras, rig, display, storage, about, apple, noise, plate
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
    var bleReady = false
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
    /// Set when one body's overlap is plainly softer than the other. Nil when they match.
    var focusGap: FocusPlace?
    var playingFocus = false
    var simulate = false
    /// High ISO reduction from the body profile. Off leaves the develop as graded.
    var highISO = false
    var noiseBusy = false
    var noiseStatus = ""
    private var noiseStop = false
    /// Sheet corrections for the plate: color, fringe, and flat.
    var plateOn = false
    /// Per-stamp Spot choice. Missing means follow the drive setting.
    private var spotPicks: [String: String] = [:]
    /// Stamps whose stitch runs the dusk curve. Missing means off. Not a drive setting.
    private var duskPicks: [String: Bool] = [:]
    var plateBusy = false
    var plateStatus = ""
    var plateFlatCount = 0
    private let plateScratch = PlateScratch()
    /// Both Nikons are recording. The shutter stops the clips and stitches them.
    var recording = false
    /// One Canon on USB. Picture and transfer only. The Nikon pair is left alone.
    var canon = false
    /// Nil keeps the hotshoe finder on. The phone camera fills the frame while the bodies are out of live view.
    var shoeOn: Bool?
    let shoe = ShoeFinder()
    var shoeEnabled: Bool { shoeOn ?? true }
    private var windowSize = CGSize.zero
    private var hingeOpen: Bool?
    private var haveWindow = false
    private var postureTask: Task<Void, Never>?
    /// Bumped whenever a camera connects, pairs, or changes live view, so the shutter and pills redraw.
    var cameraRevision = 0
    /// Bumped when a body is added, removed, or reseated. Settings pages use this, not every live frame.
    var usbRevision = 0
    /// The playback card to return to after a set is closed.
    var playbackReturn: String?
    /// Latest prism readings. The top bar shows these while auto-meter is on.
    var meterReads: [Role: MeterRead] = [:]
    /// The bar auto-meter already turned into shutter and ISO.
    var meterHeld: Int?

    let camera = CameraHub()
    private let dialT = FocusDial()
    private let dialR = FocusDial()
    private var lastPlace: FocusPlace?
    /// Sharpest the current focus window has been. Kept so a blur cannot drag the box onto a different edge.
    private var heldBest = 0.0
    private var applyTask: Task<Void, Never>?
    private var meterWatch: Task<Void, Never>?
    private var metering = false
    private var meterAppliedAt = Date.distantPast
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

    /// The on-screen release and the Camera Control button. A still already in flight stays closed. Recording stays open so the same press can stop it.
    var releaseReady: Bool {
        let _ = cameraRevision
        if shooting && !recording { return false }
        if recording || simulate { return true }
        return camera.slots.values.contains { $0.online }
    }

    /// D7000 when a paired body says so. The simulator and a D800 stay on the FX stitch. Updated when the body names change, not on every live frame.
    private(set) var bodyKind: BodyKind = .d800

    private func noteBodyKind() {
        let names = [camera.slots[.t]?.model, camera.slots[.r]?.model].compactMap { $0 }
        let next: BodyKind = names.contains(where: { BodyKind.from($0) == .d7000 }) ? .d7000 : .d800
        if next != bodyKind { bodyKind = next }
    }

    var activeMode: NamedMode? { modes.first { $0.id == activeModeID } }
    var modeDrifted: Bool {
        guard let mode = activeMode else { return false }
        return mode.photo != photo
    }

    func start() async {
        CloudShelf.merge()
        let state = Disk.load()
        photo = state.photo
        let huginMark = Disk.support.appendingPathComponent("hugin-default")
        let adoptHugin = !FileManager.default.fileExists(atPath: huginMark.path)
        if adoptHugin && photo.drive.engine == "match" { photo.drive.engine = "hugin" }
        modes = state.modes
        let addApple = !modes.contains { $0.id == "apple" }
        if addApple { modes.insert(Seed.appleMode(), at: 0) }
        let addVideo = !modes.contains { $0.id == "video" }
        if addVideo {
            let at = modes.first?.id == "apple" ? 1 : 0
            modes.insert(Seed.videoMode(), at: min(at, modes.count))
        }
        activeModeID = state.activeModeID
        rig = state.rig
        notes = state.shots
        protectedStamps = Set(state.protectedStamps)
        idleMinutes = state.idleChosen ? state.idleMinutes : 5
        idleChosen = state.idleChosen
        appleOn = state.appleOn
        metalWarp = state.metalWarp ?? true
        simulate = state.simulate
        canon = state.canon
        shoeOn = state.shoeOn
        highISO = NoiseBook.isOn
        plateOn = PlateBook.isOn
        spotPicks = Self.loadSpotPicks()
        duskPicks = Self.loadDuskPicks()
        if canon { simulate = false }
        if adoptHugin {
            try? Data("1".utf8).write(to: huginMark)
        }
        if addApple || addVideo || (adoptHugin && photo.drive.engine == "hugin") { persist() }
        camera.simulate = simulate
        camera.canonMode = canon
        camera.onChange = { [weak self] in
            guard let self else { return }
            self.noteBodyKind()
            self.cameraRevision += 1
            self.ingest()
        }
        camera.onSeat = { [weak self] in
            guard let self else { return }
            self.noteBodyKind()
            self.usbRevision += 1
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
        if photo.drive.release == "bt" {
            bleReady = await BLELink.ping()
        } else if await SyncLink.ping() {
            syncReady = true
            if photo.drive.release != "sync" {
                photo.drive.release = "sync"
                persist()
            }
            note("10-pin sync on", bad: false)
        }
        ingest()
        CloudShelf.watch { [weak self] in
            Task { @MainActor in self?.adoptCloud() }
        }
        armIdle()
        watchSync()
        armMeter()
        syncShoe()
        if ProcessInfo.processInfo.arguments.contains("-shootSim") {
            photo.drive.review = 0
            try? await Task.sleep(nanoseconds: 600_000_000)
            await fire()
        }
    }

    private var cloudWait: Task<Void, Never>?

    /// iCloud delivered a newer calibration. Idle only, so a shot in progress does not get its settings replaced.
    func adoptCloud() {
        if shooting || recording || plateBusy || noiseBusy || stitchRunning {
            guard cloudWait == nil else { return }
            cloudWait = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self.cloudWait = nil
                self.adoptCloud()
            }
            return
        }
        guard CloudShelf.merge() else { return }
        NoiseBook.forget()
        PlateBook.forget()
        let state = Disk.load()
        photo = state.photo
        modes = state.modes
        activeModeID = state.activeModeID
        rig = state.rig
        notes = state.shots
        protectedStamps = Set(state.protectedStamps)
        if state.idleChosen {
            idleMinutes = state.idleMinutes
            idleChosen = true
        }
        appleOn = state.appleOn
        if let warp = state.metalWarp { metalWarp = warp }
        simulate = state.simulate
        canon = state.canon
        shoeOn = state.shoeOn
        highISO = NoiseBook.isOn
        plateOn = PlateBook.isOn
        spotPicks = Self.loadSpotPicks()
        duskPicks = Self.loadDuskPicks()
        camera.simulate = simulate
        camera.canonMode = canon
        camera.adoptPair()
        ingest()
        applyIdle()
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
        if phase == .active { shoe.allowRetry() }
        syncShoe()
    }

    /// The frame is showing Shoe and the camera is down. Start it again.
    func reviveShoe() {
        guard shoeEnabled, !camera.live, !sleeping, !shooting, !recording, scenePhase == .active else { return }
        guard !shoe.running else { return }
        shoe.start(kind: bodyKind)
    }

    func setShoe(_ on: Bool) {
        shoeOn = on
        persist()
        if on { shoe.allowRetry() }
        syncShoe()
    }

    /// The window and the hinge. A fully open landscape Duo uses its rear cameras. The cover keeps the outer one.
    func noteWindow(_ size: CGSize) {
        guard size.width > 2, size.height > 2 else { return }
        let first = !haveWindow
        haveWindow = true
        windowSize = size
        if first {
            applyShoePosture()
        } else {
            postureTask?.cancel()
            postureTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
                applyShoePosture()
            }
        }
    }

    func noteHinge(fullyOpen: Bool?) {
        guard fullyOpen != hingeOpen else { return }
        hingeOpen = fullyOpen
        applyShoePosture()
    }

    /// Landscape on the unfolded screen, or the hinge open flat in landscape. A phone-sized cover stays on the outer camera.
    private func applyShoePosture() {
        guard ShoePhone.current == .duo else {
            shoe.setFlat(false)
            return
        }
        let landscape = windowSize.width > windowSize.height
        let unfolded = min(windowSize.width, windowSize.height) > 500
        let flat = landscape && (unfolded || hingeOpen == true)
        shoe.setFlat(flat)
    }

    /// The phone camera fills the frame only while the bodies are out of live view.
    private func syncShoe() {
        let want = shoeEnabled && !camera.live && !sleeping && !shooting && !recording && scenePhase == .active
        if want {
            shoe.start(kind: bodyKind)
        } else if shoe.running {
            shoe.stop()
        }
    }

    func go(_ next: Route) { route.append(next) }
    func home() { route.removeAll() }
    func back() { if !route.isEmpty { route.removeLast() } }

    func edit(_ body: (inout Photo) -> Void) {
        let wasAuto = photo.light.autoMeter
        body(&photo)
        persist()
        scheduleApply()
        ingest()
        if photo.drive.release == "bt" {
            Task { await probeSync() }
        } else {
            BLELink.stop()
            bleReady = false
        }
        if photo.light.autoMeter != wasAuto { armMeter() }
    }

    func editRig(_ body: (inout Rig) -> Void) {
        body(&rig)
        persist()
        ingest()
    }

    func setHighISO(_ on: Bool) {
        highISO = on
        NoiseBook.setOn(on)
    }

    func setPlate(_ on: Bool) {
        plateOn = on
        PlateBook.setOn(on)
    }

    /// One paired frame of the printed sheet. Color and fringe are a single shot. The flat is four, with a slide between them.
    func shootPlate(_ job: PlateJob) {
        if plateBusy {
            return
        }
        if noiseBusy || shooting || recording {
            plateStatus = "Wait for the shutter"
            return
        }
        if canon {
            plateStatus = "The sheet run drives the Nikon pair"
            return
        }
        let ready = Role.allCases.filter { role in
            let slot = camera.slots[role] ?? BodyState()
            return slot.paired && slot.online
        }
        if ready.count < 2 && !simulate {
            plateStatus = "Pair both bodies on USB first"
            return
        }
        plateBusy = true
        shooting = true
        let label: String
        switch job {
        case .color: label = "Shooting the gray"
        case .fringe: label = "Shooting the rules"
        case .flat: label = "Shooting flat \(plateFlatCount + 1) of 4"
        }
        plateStatus = label
        let restore = photo
        let wasLive = camera.live
        Task {
            defer {
                self.plateBusy = false
                self.shooting = false
                let photo = self.photo
                Task {
                    await self.camera.apply(photo, force: true)
                    if wasLive { await self.camera.setLive(true) }
                }
            }
            do {
                let pair = try await self.camera.platePair(photo: restore)
                self.keepPlate(job, pair)
            } catch {
                self.plateStatus = error.localizedDescription
            }
        }
    }

    /// Color and fringe from the newest stitch that actually lined up. One frame cannot be the flat: the room light would be stored as the plate.
    func measureSavedPlate() {
        if plateBusy || noiseBusy || shooting || recording {
            plateStatus = "Wait for the shutter"
            return
        }
        reloadShots()
        guard let shot = goodPlateShot() else {
            plateStatus = "No lined-up stitch to measure. The pair that missed is left out."
            return
        }
        plateBusy = true
        plateStatus = "Measuring \(shot.name)"
        Task {
            defer { self.plateBusy = false }
            guard let tURL = plateFile(shot.t, shot.nefT), let rURL = plateFile(shot.r, shot.nefR),
                  let tImage = Stitcher.thumbnail(at: tURL, maxPixel: 1600),
                  let rImage = Stitcher.thumbnail(at: rURL, maxPixel: 1600) else {
                self.plateStatus = "Could not read \(shot.name)"
                return
            }
            let tWho = NoiseBook.identity(tURL)
            let rWho = NoiseBook.identity(rURL)
            let pair: [Role: NoiseGrab] = [
                .t: NoiseGrab(image: tImage, iso: tWho.iso, serial: tWho.serial, model: tWho.model),
                .r: NoiseGrab(image: rImage, iso: rWho.iso, serial: rWho.serial, model: rWho.model),
            ]
            self.keepPlate(.color, pair)
            let color = self.plateStatus
            if color.hasPrefix("The gray") || color.hasPrefix("One body") {
                return
            }
            self.keepPlate(.fringe, pair)
            let fringe = self.plateStatus
            if fringe.hasPrefix("The rules") || fringe.hasPrefix("One body") {
                self.plateStatus = "From \(shot.name). \(color)"
                return
            }
            self.plateStatus = "From \(shot.name). \(color) \(fringe) The flat stays out of this frame. The light on the sheet would be saved as if it were the plate."
        }
    }

    private func plateFile(_ jpeg: URL?, _ nef: URL?) -> URL? {
        if let jpeg, !NoiseBook.identity(jpeg).serial.isEmpty { return jpeg }
        if let nef, !NoiseBook.identity(nef).serial.isEmpty { return nef }
        return jpeg ?? nef
    }

    private func goodPlateShot() -> ShotFiles? {
        for shot in shots where (shot.t ?? shot.nefT) != nil && (shot.r ?? shot.nefR) != nil {
            guard let report = stitchReport(shot) else { continue }
            if report.blend == "multiband", (report.inliers ?? 0) >= 20 { return shot }
        }
        return nil
    }

    private func stitchReport(_ shot: ShotFiles) -> StitchReport? {
        let url = Disk.captures.appendingPathComponent("P_\(shot.stamp).json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StitchReport.self, from: data)
    }

    func resetPlateFlats() {
        plateScratch.shots.removeAll()
        plateFlatCount = 0
        plateStatus = "Flats cleared. Aim the gray at one part of the frame, then shoot flat 1 of 4."
    }

    /// The sheet shots and anything they stored. A restitch after this is the frame without them.
    func clearSavedPlate() {
        plateScratch.shots.removeAll()
        plateFlatCount = 0
        PlateBook.clearMeasurements()
        setPlate(false)
        plateStatus = "Saved plate cleared. Correction is off. Restitch for the frame without it."
    }

    private func doorNote(_ image: CGImage) -> String {
        PlateField.trimmedDoor(image) ? " The door around the sheet was left out." : ""
    }

    private func keepPlate(_ job: PlateJob, _ pair: [Role: NoiseGrab]) {
        guard let t = pair[.t], let r = pair[.r], !t.serial.isEmpty, !r.serial.isEmpty else {
            plateStatus = "One body came back without a serial"
            return
        }
        switch job {
        case .color:
            guard let tm = PlateField.gray(t.image), let rm = PlateField.gray(r.image), tm.neutral, rm.neutral else {
                plateStatus = "The gray on the sheet was not even enough. A reflection on the paper still counts. Shift until that gray is flat, then shoot again."
                return
            }
            PlateBook.update(t.serial, model: t.model) {
                $0.reference = t.serial
                $0.gainR = 1
                $0.gainG = 1
                $0.gainB = 1
            }
            let gr = tm.r / max(rm.r, 0.002)
            let gg = tm.g / max(rm.g, 0.002)
            let gb = tm.b / max(rm.b, 0.002)
            PlateBook.update(r.serial, model: r.model) {
                $0.reference = t.serial
                $0.gainR = min(1.6, max(0.6, gr))
                $0.gainG = min(1.6, max(0.6, gg))
                $0.gainB = min(1.6, max(0.6, gb))
            }
            setPlate(true)
            plateStatus = String(format: "Gray saved. R against T: red %+.1f%%, green %+.1f%%, blue %+.1f%%. Turn the sheet to the rules.", (gr - 1) * 100, (gg - 1) * 100, (gb - 1) * 100) + doorNote(t.image)
        case .fringe:
            var saved = 0
            var note = ""
            for grab in [t, r] {
                guard let fit = PlateField.fringe(grab.image) else { continue }
                PlateBook.update(grab.serial, model: grab.model) {
                    $0.caR = fit.caR
                    $0.caB = fit.caB
                }
                saved += 1
                note += String(format: " %@ red %+.2f%% blue %+.2f%%.", grab.model, fit.caR * 100, fit.caB * 100)
            }
            if saved == 0 {
                plateStatus = "The rules on the sheet were not clear enough. Square the grid to the rig. A reflection on the paper still counts."
                return
            }
            setPlate(true)
            plateStatus = "Rules saved.\(note) Put the gray back for the four flats." + doorNote(t.image)
        case .flat:
            plateScratch.shots[.t, default: []].append(t.image)
            plateScratch.shots[.r, default: []].append(r.image)
            plateFlatCount = min(plateScratch.shots[.t]?.count ?? 0, plateScratch.shots[.r]?.count ?? 0)
            if plateFlatCount < 4 {
                plateStatus = "Flat \(plateFlatCount) of 4. Move the sheet so the gray covers a part of the frame it has not covered yet." + doorNote(t.image)
                return
            }
            var lines: [String] = []
            for role in [Role.t, Role.r] {
                guard let grab = pair[role] else { continue }
                let frames = plateScratch.shots[role] ?? []
                guard let made = PlateField.flat(frames) else { continue }
                PlateBook.update(grab.serial, model: grab.model) {
                    $0.flatW = made.w
                    $0.flatH = made.h
                    $0.flat = made.values
                }
                let body = PlateBook.bodies().first { NoiseBook.sameSerial($0.serial, grab.serial) }
                if let fall = body?.cornerFall() {
                    lines.append(String(format: "%@ corner %+.0f%%", grab.model, fall * 100))
                }
            }
            plateScratch.shots.removeAll()
            plateFlatCount = 0
            if lines.isEmpty {
                plateStatus = "The sheet's grid was still in the flat, so nothing was saved. Move the gray to a new part of the frame for each of the four shots, then start again."
                return
            }
            setPlate(true)
            plateStatus = "Flat saved. " + lines.joined(separator: ", ") + ". Plate correction is on." + doorNote(t.image)
        }
    }

    /// Fire each paired body through a manual ISO and shutter walk, then store variance = a × mean + b on its serial.
    func profileNoise() {
        if noiseBusy {
            noiseStop = true
            noiseStatus = "Stopping"
            return
        }
        if shooting || recording {
            noiseStatus = "Wait for the shutter"
            return
        }
        if canon {
            noiseStatus = "The profiler drives the Nikon pair"
            return
        }
        let ready = Role.allCases.filter { role in
            let slot = camera.slots[role] ?? BodyState()
            return slot.paired && slot.online
        }
        if ready.isEmpty && !simulate {
            noiseStatus = "Pair a body on USB first"
            return
        }
        let roles = ready.isEmpty ? [Role.t, Role.r] : ready
        let isos = ["200", "800", "1600", "3200", "6400"]
        let shutters = ["1/1000", "1/60", "1/4"]
        let total = roles.count * isos.count * shutters.count
        noiseBusy = true
        noiseStop = false
        shooting = true
        noiseStatus = "Starting"
        Task {
            defer {
                self.noiseBusy = false
                self.shooting = false
                self.noiseStop = false
                let photo = self.photo
                Task { await self.camera.apply(photo, force: true) }
            }
            await self.camera.setLive(false)
            var bag: [String: (model: String, samples: [NoiseSample])] = [:]
            var lastError: String?
            var step = 0
            var halt = false
            for role in roles {
                for iso in isos {
                    for shutter in shutters {
                        if self.noiseStop { halt = true; break }
                        await Task.yield()
                        step += 1
                        self.noiseStatus = "\(role.rawValue) \(step)/\(total)  ISO \(iso)  \(Catalog.fmtShut(shutter))"
                        do {
                            let shot = try await self.camera.profileFrame(role: role, iso: iso, shutter: shutter)
                            guard !shot.serial.isEmpty, shot.iso > 0 else {
                                lastError = "\(role.rawValue) came back without a serial"
                                continue
                            }
                            let stats = NoiseField.measure(shot.image)
                            var row = bag[shot.serial] ?? (model: shot.model, samples: [])
                            row.model = shot.model
                            row.samples.append(NoiseSample(
                                iso: shot.iso, shutter: shutter,
                                meanR: stats.mr, meanG: stats.mg, meanB: stats.mb,
                                varR: stats.vr, varG: stats.vg, varB: stats.vb
                            ))
                            bag[shot.serial] = row
                        } catch {
                            lastError = error.localizedDescription
                            self.noiseStatus = "\(role.rawValue) ISO \(iso) \(Catalog.fmtShut(shutter)): \(error.localizedDescription)"
                        }
                    }
                    if halt { break }
                }
                if halt { break }
            }
            let made = bag.map { NoiseBook.make(serial: $0.key, model: $0.value.model, samples: $0.value.samples) }
            if made.isEmpty {
                self.noiseStatus = halt ? "Stopped" : (lastError ?? "No frame came back")
                return
            }
            NoiseBook.save(made)
            let useful = made.contains { $0.rises() }
            if useful { self.setHighISO(true) }
            let names = made.map { "\($0.model) \($0.serial)" }.joined(separator: ", ")
            if halt {
                self.noiseStatus = "Stopped. Saved \(names)."
            } else if useful {
                self.noiseStatus = "Saved \(names)"
            } else {
                self.noiseStatus = "Saved \(names). The frames stayed flat across ISO. Point the bodies at a dim, even wall and run it again."
            }
        }
    }

    func setSimulate(_ on: Bool) {
        simulate = on
        camera.simulate = on
        if on, canon {
            canon = false
            Task { await camera.setCanonMode(false) }
        }
        persist()
        ingest()
    }

    func setCanon(_ on: Bool) {
        canon = on
        if on, simulate {
            simulate = false
            camera.simulate = false
        }
        persist()
        Task { await camera.setCanonMode(on) }
        note(on ? "Canon · one body" : "Nikon pair", bad: false)
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
        syncShoe()
    }

    /// A touch. Restarts the sleep clock, and brings the bodies back if they had been released.
    func poke() {
        let now = Date()
        if sleeping {
            sleeping = false
            lastPoke = now
            Task { await camera.wakeFromIdle() }
            armIdle()
            syncShoe()
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
        if photo.drive.release == "bt" {
            bleReady = await BLELink.ping()
            return
        }
        syncReady = await SyncLink.ping()
    }

    /// Keeps the top-bar Sync mark current. A ping during a release would sit on the same socket as FIRE.
    private func watchSync() {
        syncWatch?.cancel()
        syncWatch = Task { [weak self] in
            while let self, !Task.isCancelled {
                if self.photo.drive.release == "sync" || self.photo.drive.release == "bt" {
                    await self.probeSync()
                } else if self.bleReady {
                    BLELink.stop()
                    self.bleReady = false
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func toggleLive() async {
        if recording { return }
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
                    FocusMeter.read(frame, aim: aim, overlap: overlap, only: nil, hold: hold, holdBest: best, tOnLeft: page.tOnLeft)
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
        var tOnLeft: Bool
    }

    private struct PanoOverlap: Decodable {
        var overlap: Double?
        var turned: Bool?
        var sceneMirror: Bool?
        var height: Int?
    }

    /// Captured stitches in the library, newest first. The overlap written beside each file places R and T.
    private func focusPages() -> [FocusPage] {
        shots.compactMap(\.pano).compactMap { url in
            guard let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
            let note = storedNote(beside: url)
            let overlap = note?.overlap ?? rig.overlap
            let hand = Stitcher.hand(turned: note?.turned, sceneMirror: note?.sceneMirror, savedHeight: note?.height)
            let shown = hand.flop ? Stitcher.flop(image) : image
            return FocusPage(image: shown, overlap: overlap, tOnLeft: hand.tOnLeft)
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

    private func storedNote(beside jpeg: URL) -> PanoOverlap? {
        let json = jpeg.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: json),
              let note = try? JSONDecoder().decode(PanoOverlap.self, from: data) else { return nil }
        guard let overlap = note.overlap, overlap > 0.05, overlap < 0.55 else {
            return PanoOverlap(overlap: nil, turned: note.turned, sceneMirror: note.sceneMirror, height: note.height)
        }
        return note
    }

    func fire() async {
        if photo.drive.movie && !canon {
            if recording {
                await finishMovie()
            } else if !shooting {
                await beginMovie()
            }
            return
        }
        if shooting { return }
        shooting = true
        let wait = photo.drive.timer
        if wait > 0 {
            for s in stride(from: wait, through: 1, by: -1) {
                countdown = s
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdown = nil
        }
        let viewfinder = await shoe.snapshot()
        ingest()
        let stamp = CaptureIndex.stampNow()
        if let viewfinder {
            let url = Disk.captures.appendingPathComponent("V_\(stamp).jpg")
            try? Stitcher.jpeg(viewfinder, to: url)
        }
        do {
            let grabbed = try await camera.capture(stamp: stamp, photo: photo) {
                guard self.photo.light.autoMeter, !self.sleeping, !self.canon else { return self.photo }
                await self.pullMeter(force: true, write: false)
                return self.photo
            }
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

    private func beginMovie() async {
        if photo.drive.timer > 0 {
            for s in stride(from: photo.drive.timer, through: 1, by: -1) {
                countdown = s
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            countdown = nil
        }
        do {
            try await camera.startMovie(photo)
            recording = true
            note("Recording", bad: false)
        } catch {
            recording = false
            note(error.localizedDescription, bad: true)
        }
        ingest()
    }

    private func finishMovie() async {
        shooting = true
        recording = false
        let stamp = CaptureIndex.stampNow()
        stitchLabel = "Stopping"
        ingest()
        do {
            let clips = try await camera.stopMovie(stamp: stamp)
            guard let t = clips[.t], let r = clips[.r] else { throw PTPError.message("Need both clips") }
            try await stitchVideo(stamp: stamp, t: t, r: r, gap: camera.movieGap)
            notes[stamp] = ShotNote(modeName: activeMode?.name ?? "Video", look: LookBook.name(photo.look), squeeze: photo.frame.squeeze)
            persist()
            reloadShots()
            note(stamp, bad: false)
        } catch {
            note(error.localizedDescription, bad: true)
        }
        shooting = false
        stitchLabel = nil
        countdown = nil
        ingest()
    }

    private func stitchVideo(stamp: String, t: URL, r: URL, gap: Double?) async throws {
        let movie = Disk.captures.appendingPathComponent("P_\(stamp).mov")
        let poster = Disk.captures.appendingPathComponent("P_\(stamp).jpg")
        let mirrorScene = shots.first(where: { $0.stamp == stamp }).map { Stitcher.mirrorScene(shot: $0) } ?? bodyKind.mirrorScene
        try await PanoVideo.make(t: t, r: r, movie: movie, poster: poster, rig: rig, gap: gap, mirrorScene: mirrorScene) { [weak self] text in
            Task { @MainActor in self?.stitchLabel = text }
        }
    }

    /// Run the clip stitch again from the two camera movies already on the phone.
    func restitchVideo(_ stamp: String) async {
        guard !shooting, !recording,
              let shot = shots.first(where: { $0.stamp == stamp }),
              let t = shot.movT, let r = shot.movR else { return }
        shooting = true
        stitchLabel = "Stitching"
        ingest()
        do {
            let saved = PanoVideo.savedGap(movie: Disk.captures.appendingPathComponent("P_\(stamp).mov"))
            try await stitchVideo(stamp: stamp, t: t, r: r, gap: saved)
            reloadShots()
            note("Stitched \(stamp)", bad: false)
        } catch {
            note(error.localizedDescription, bad: true)
        }
        shooting = false
        stitchLabel = nil
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

    /// Delete every set, or only those from before today. Protected sets stay.
    func deleteShots(beforeToday: Bool) {
        let today = Self.dayString(Date())
        var removed = 0
        var spared = 0
        var cancelStitch = false
        for shot in shots {
            if beforeToday {
                guard let day = Self.day(of: shot.stamp), day < today else { continue }
            }
            if protectedStamps.contains(shot.stamp) {
                spared += 1
                continue
            }
            droppedStamps.insert(shot.stamp)
            stitchQueue.removeAll { $0 == shot.stamp }
            stitchWaiting.remove(shot.stamp)
            if stitchingStamp == shot.stamp { cancelStitch = true }
            CaptureIndex.delete(stamp: shot.stamp)
            notes[shot.stamp] = nil
            if reviewStamp == shot.stamp { reviewStamp = nil }
            route.removeAll {
                if case .shot(let stamp) = $0 { return stamp == shot.stamp }
                return false
            }
            removed += 1
        }
        if cancelStitch {
            stitchStop.cancel()
            stitchPiece?.cancel()
        }
        guard removed > 0 else {
            note(spared > 0 ? "Protected" : (beforeToday ? "Nothing older than today" : "No sets yet"), bad: spared > 0)
            return
        }
        persist()
        reloadShots()
        ingest()
        if spared > 0 {
            note("Deleted \(removed) · \(spared) protected", bad: false)
        } else {
            note("Deleted \(removed)", bad: false)
        }
    }

    private static func day(of stamp: String) -> String? {
        let digits = stamp.filter(\.isNumber)
        guard digits.count >= 8 else { return nil }
        return String(digits.prefix(8))
    }

    private static func dayString(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
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

    /// Drive follows the Drive screen. On and Off apply to this set only.
    func spotChoice(_ stamp: String) -> String {
        spotPicks[stamp] ?? "drive"
    }

    func chooseSpot(_ stamp: String, _ choice: String) {
        if choice == "drive" {
            spotPicks.removeValue(forKey: stamp)
        } else {
            spotPicks[stamp] = choice
        }
        if let data = try? JSONEncoder().encode(spotPicks) {
            try? data.write(to: Disk.support.appendingPathComponent("spot.json"), options: .atomic)
        }
        restitch(stamp)
    }

    private static func loadSpotPicks() -> [String: String] {
        let url = Disk.support.appendingPathComponent("spot.json")
        guard let data = try? Data(contentsOf: url),
              let picks = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return picks
    }

    /// Off until this set is switched on. It does not follow Drive.
    func duskOn(_ stamp: String) -> Bool {
        duskPicks[stamp] == true
    }

    func chooseDusk(_ stamp: String, _ on: Bool) {
        if on {
            duskPicks[stamp] = true
        } else {
            duskPicks.removeValue(forKey: stamp)
        }
        if let data = try? JSONEncoder().encode(duskPicks) {
            try? data.write(to: Disk.support.appendingPathComponent("dusk.json"), options: .atomic)
        }
        restitch(stamp)
    }

    private static func loadDuskPicks() -> [String: Bool] {
        let url = Disk.support.appendingPathComponent("dusk.json")
        guard let data = try? Data(contentsOf: url),
              let picks = try? JSONDecoder().decode([String: Bool].self, from: data) else { return [:] }
        return picks
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
        syncShoe()
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
        let mirrorScene = bodyKind.mirrorScene
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
                let asked = [Role.t, .r].compactMap { self.camera.frameAsked[$0] }.min()
                let started = CFAbsoluteTimeGetCurrent()
                let made = await Task.detached(priority: .userInitiated) {
                    Self.makePreview(t: t, r: r, rig: rig, photo: photo, fallback: panoURL, meter: meter, aim: aim, hold: hold, holdBest: best, mirrorScene: mirrorScene)
                }.value
                let now = CFAbsoluteTimeGetCurrent()
                self.clockPreview(now - started, age: asked.map { now - $0 } ?? 0, look: LookBook.identity(photo.look) ? "none" : photo.look.base, aid: photo.focus.aid)
                if self.playingFocus { continue }
                if let image = made.image {
                    self.preview = image
                }
                self.focusGap = made.soft
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

    private var previewClock: (count: Int, total: Double, worst: Double, age: Double, oldest: Double, since: CFAbsoluteTime) = (0, 0, 0, 0, 0, 0)

    /// `age` runs from the GetLiveView request of the older frame in the stitch to the preview being handed to the screen.
    private func clockPreview(_ seconds: Double, age: Double, look: String, aid: String) {
        guard camera.live else { return }
        if previewClock.count == 0 { previewClock.since = CFAbsoluteTimeGetCurrent() }
        previewClock.count += 1
        previewClock.total += seconds
        previewClock.worst = max(previewClock.worst, seconds)
        previewClock.age += age
        previewClock.oldest = max(previewClock.oldest, age)
        guard previewClock.count >= 30 else { return }
        let wall = CFAbsoluteTimeGetCurrent() - previewClock.since
        let n = Double(previewClock.count)
        Trace.line(String(format: "FXPAN preview %.1f fps, build avg %.0f ms max %.0f ms, frame age avg %.0f ms max %.0f ms, look %@ aid %@",
                          n / max(wall, 0.001), previewClock.total / n * 1000, previewClock.worst * 1000,
                          previewClock.age / n * 1000, previewClock.oldest * 1000, look, aid))
        previewClock = (0, 0, 0, 0, 0, 0)
    }

    private struct PreviewMade {
        var image: UIImage?
        var score: Double?
        var box: CGRect?
        var sharp: CGRect?
        var place: FocusPlace = .both
        var holdBest: Double = 0
        var soft: FocusPlace?
    }

    nonisolated private static func makePreview(t: CGImage?, r: CGImage?, rig: Rig, photo: Photo, fallback: URL?, meter: Bool, aim: CGPoint?, hold: CGRect?, holdBest: Double, mirrorScene: Bool) -> PreviewMade {
        if let t, let r, let cg = Stitcher.preview(t: t, r: r, rig: rig, squeeze: photo.frame.squeeze, maxWidth: 1400, mirrorScene: mirrorScene) {
            let overlap = rig.overlap(width: t.width, height: t.height)
            let soft = FocusMeter.softer(t: t, r: r, flipR: rig.flipR, overlap: overlap)
            let read = meter ? FocusMeter.read(cg, aim: aim, overlap: overlap, only: nil, hold: hold, holdBest: holdBest, tOnLeft: mirrorScene) : FocusRead()
            var out = cg
            if !LookBook.identity(photo.look) { out = Stitcher.grade(out, look: photo.look) }
            if photo.focus.aid == "peaking" { out = Peak.draw(out, color: photo.focus.color, level: photo.focus.level) }
            return PreviewMade(image: UIImage(cgImage: out), score: read.score, box: read.box, sharp: read.sharp, place: read.place, holdBest: read.holdBest, soft: soft)
        }
        if let t {
            let shown = Stitcher.present(t, flopBody: false, mirrorScene: mirrorScene)
            let read = meter ? FocusMeter.read(shown, aim: aim, overlap: rig.overlap, only: .t, hold: hold, holdBest: holdBest) : FocusRead(place: .t)
            return PreviewMade(image: UIImage(cgImage: shown), score: read.score, box: read.box, sharp: read.sharp, place: read.place, holdBest: read.holdBest)
        }
        if let r {
            let shown = Stitcher.present(r, flopBody: rig.flipR, mirrorScene: mirrorScene)
            let read = meter ? FocusMeter.read(shown, aim: aim, overlap: rig.overlap, only: .r, hold: hold, holdBest: holdBest) : FocusRead(place: .r)
            return PreviewMade(image: UIImage(cgImage: shown), score: read.score, box: read.box, sharp: read.sharp, place: read.place, holdBest: read.holdBest)
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

    /// Poll the prism while auto-meter is on. Sleep, a recording, and a shot in progress leave the bodies alone.
    private func armMeter() {
        meterWatch?.cancel()
        meterWatch = nil
        guard photo.light.autoMeter else {
            meterReads = [:]
            meterHeld = nil
            return
        }
        meterWatch = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                if self.photo.light.autoMeter, !self.sleeping, !self.shooting, !self.recording, !self.canon, self.scenePhase == .active {
                    await self.pullMeter(force: false)
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Read both bars, move shutter and ISO to the aim, and write the bodies when the proposal changes.
    private func pullMeter(force: Bool, write: Bool = true) async {
        while metering {
            try? await Task.sleep(nanoseconds: 40_000_000)
            if Task.isCancelled { return }
        }
        metering = true
        defer { metering = false }
        var reads = await camera.readMeters()
        meterReads = reads
        guard photo.light.autoMeter, !canon else { return }
        let master = Role(rawValue: photo.light.master) ?? .t
        // The prism is blind with the mirror up. A frozen count would pin the dials for the whole live view.
        guard reads[master]?.mirrorUp != true else { return }
        // Right after the mirror drops, the first get is often the count from before. Wait once and read it again.
        if force, let held = reads[master]?.counts, held == meterHeld, abs(held - ExposureMeter.targetCounts) > 2 {
            try? await Task.sleep(nanoseconds: 400_000_000)
            reads = await camera.readMeters()
            meterReads = reads
            guard reads[master]?.mirrorUp != true else { return }
        }
        let aim = ExposureMeter.aim(of: photo.light)
        // The prism bar ends at five stops. A pegged reading is applied, then read again, until it comes off the end.
        let passes = force ? 4 : 1
        for pass in 0..<passes {
            guard let counts = reads[master]?.counts else { return }
            if !force, counts == meterHeld { return }
            let pegged = abs(counts) >= 60
            let chase = force && pegged && pass + 1 < passes
            guard await commitMeter(reads[master], counts: counts, aim: aim, force: force, write: write || chase) else { return }
            guard chase else { return }
            try? await Task.sleep(nanoseconds: 350_000_000)
            reads = await camera.readMeters()
            meterReads = reads
            guard reads[master]?.mirrorUp != true, let next = reads[master]?.counts, next != counts else { return }
        }
    }

    /// Write one prism correction into the photo, and onto the bodies when `write` is set.
    private func commitMeter(_ sample: MeterRead?, counts: Int, aim: MeterAim, force: Bool, write: Bool) async -> Bool {
        let plan = ExposureMeter.plan(
            master: Role(rawValue: photo.light.master) ?? .t,
            read: sample,
            shutter: photo.light.shutter,
            iso: photo.light.iso,
            kind: bodyKind,
            aim: aim
        )
        guard plan.ready, let shutter = plan.shutter, let iso = plan.iso else { return false }
        if !force, Date().timeIntervalSince(meterAppliedAt) < 1.5 { return false }
        photo.light.program = "M"
        photo.light.followCam = false
        photo.light.bulb = false
        photo.light.shutter = shutter
        photo.light.iso = iso
        meterHeld = counts
        meterAppliedAt = Date()
        Trace.line("FXPAN meter \(counts) → \(shutter) \(iso)")
        persist()
        ingest()
        applyTask?.cancel()
        if write { await camera.apply(photo, readBack: false) }
        return true
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
        var photo = photo
        switch spotPicks[stamp] {
        case "on": photo.drive.spot = true
        case "off": photo.drive.spot = false
        default: break
        }
        let mirrorScene = bodyKind.mirrorScene
        let dusk = duskPicks[stamp] == true
        do {
            let note: StitchNote = { phase in
                Task { @MainActor in self.noteStitch(phase) }
            }
            let stop = stitchStop
            let metal = metalWarp
            let job = Task.detached(priority: .userInitiated) {
                try Stitcher.write(tURL: t, rURL: r, dest: dest, ana: ana, rig: rig, photo: photo, metal: metal, mirrorScene: mirrorScene, dusk: dusk, note: note, stop: { stop.cancelled })
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
            Disk.mirrorLatest()
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
        state.canon = canon
        state.shoeOn = shoeOn
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
        if shooting || recording {
            armIdle()
            return
        }
        guard !sleeping else { return }
        sleeping = true
        idleTask?.cancel()
        idleTask = nil
        syncShoe()
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
