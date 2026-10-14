import AVFoundation
import CoreGraphics
import ImageIO
import UIKit

/// Line the two clips up in time, solve the still Hugin fit once, and warp every frame with that fit.
enum PanoVideo {
    /// `gap` is the seconds R started after T, measured when both start commands went out. Nil when it was never measured.
    static func make(
        t: URL, r: URL, movie: URL, poster: URL, rig: Rig, gap: Double?,
        note: @escaping @Sendable (String) -> Void
    ) async throws {
        note("Matching the clips")
        let timing = try await Task.detached(priority: .userInitiated) {
            try await offset(t: t, r: r, gap: gap)
        }.value
        let lag = timing.lag
        note("Fitting the overlap")
        let held = try await Task.detached(priority: .userInitiated) {
            try await lock(t: t, r: r, rig: rig, lag: lag)
        }.value
        guard let held else { throw PTPError.message("Could not fit the overlap") }
        note("Stitching")
        let made = try await Task.detached(priority: .userInitiated) {
            try await render(t: t, r: r, movie: movie, poster: poster, rig: rig, lag: lag, hold: held, note: note)
        }.value
        note("\(made.frames) frames")
        let line = lag == 0 ? "in step" : "offset \(lag) frames"
        var report = StitchReport(
            overlap: made.overlap, overlapPx: 0, dy: made.dy, flipR: rig.flipR,
            mode: "video hugin",
            width: made.width, height: made.height, squeeze: 1, look: "video",
            rot: made.rot, scale: made.scale, inliers: made.inliers, blend: "\(made.blend) · \(line)"
        )
        report.sec = Double(made.frames) / Double(max(made.fps, 1))
        report.startGap = gap
        report.lag = lag
        report.turned = true
        let json = movie.deletingPathExtension().appendingPathExtension("json")
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: json, options: .atomic)
        }
    }

    /// The start gap saved by an earlier stitch, so a second run searches the same window.
    static func savedGap(movie: URL) -> Double? {
        let json = movie.deletingPathExtension().appendingPathExtension("json")
        guard let data = try? Data(contentsOf: json),
              let report = try? JSONDecoder().decode(StitchReport.self, from: data) else { return nil }
        return report.startGap
    }

    /// A short pair so the stitch can run with no cameras. The bar sits in the overlap, three frames late on R.
    static func sample(stamp: String) throws -> [Role: URL] {
        let t = Disk.captures.appendingPathComponent("T_\(stamp).mov")
        let r = Disk.captures.appendingPathComponent("R_\(stamp).mov")
        try clip(to: t, delay: 0)
        try clip(to: r, delay: 3)
        return [.t: t, .r: r]
    }

    private struct Made {
        var frames: Int
        var fps: Int
        var width: Int
        var height: Int
        var overlap: Double
        var dy: Int
        var rot: Double
        var scale: Double
        var inliers: Int
        var blend: String
    }

    // MARK: - Timing

    /// T frame i pairs with R frame i + lag. R starting later gives a negative lag, and T skips those frames.
    /// The two pictures share only the overlap, so the sound is what lines them up. Both mics hear the same moment.
    /// The picture match is the fallback when a body recorded no sound.
    private static func offset(t: URL, r: URL, gap: Double?) async throws -> (lag: Int, score: Double) {
        let fps = max(try await rate(t), try await rate(r))
        let prior = gap.map { Int((-$0 * fps).rounded()) } ?? 0
        let reach = gap == nil ? Int(fps * 6) : Int(fps * 1.5)
        if let heard = try await sound(t, r, fps: fps),
           let found = slide(zscore(heard.t), zscore(heard.r), prior: prior, reach: reach),
           found.score >= 0.35 {
            Trace.line(String(format: "FXPAN video timing audio gap %@ prior %d search ±%d best %d corr %.2f use %d",
                              gap.map { String(format: "%+.3fs", $0) } ?? "none", prior, reach, found.lag, found.score, found.lag))
            return (found.lag, found.score)
        }
        let a = try await motion(t)
        let b = try await motion(r)
        let found = slide(zscore(a.curve), zscore(b.curve), prior: prior, reach: reach)
        let trusted = (found?.score ?? -1) >= 0.25
        let lag = trusted ? (found?.lag ?? prior) : prior
        Trace.line(String(format: "FXPAN video timing picture gap %@ prior %d search ±%d best %d corr %.2f use %d",
                          gap.map { String(format: "%+.3fs", $0) } ?? "none", prior, reach, found?.lag ?? prior, found?.score ?? -1, lag))
        return (lag, found?.score ?? -1)
    }

    /// Loudness of each video frame. The waveform itself does not match: the mics are not in phase.
    private static func sound(_ t: URL, _ r: URL, fps: Double) async throws -> (t: [Double], r: [Double])? {
        async let a = envelope(t, fps: fps)
        async let b = envelope(r, fps: fps)
        let heardT = try await a
        let heardR = try await b
        guard let heardT, let heardR, heardT.count > 8, heardR.count > 8 else {
            Trace.line("FXPAN video timing audio none")
            return nil
        }
        return (heardT, heardR)
    }

    private static func envelope(_ url: URL, fps: Double) async throws -> [Double]? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first,
              let desc = try await track.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee else { return nil }
        let channels = max(1, Int(asbd.mChannelsPerFrame))
        let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
        let per = max(1, Int((rate / fps).rounded()))
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = true
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }
        defer { reader.cancelReading() }
        var bins: [Double] = []
        var counts: [Int] = []
        while let sample = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            guard length >= 2 else { continue }
            var bytes = [UInt8](repeating: 0, count: length)
            guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &bytes) == noErr else { continue }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let origin = pts.isFinite ? Int((pts * rate).rounded()) : 0
            bytes.withUnsafeBytes { raw in
                let samples = raw.bindMemory(to: Int16.self)
                let frames = samples.count / channels
                for i in 0..<frames {
                    var acc = 0
                    for c in 0..<channels { acc += abs(Int(samples[i * channels + c])) }
                    let bin = (origin + i) / per
                    guard bin >= 0 else { continue }
                    if bin >= bins.count {
                        bins.append(contentsOf: repeatElement(0, count: bin - bins.count + 1))
                        counts.append(contentsOf: repeatElement(0, count: bin - counts.count + 1))
                    }
                    bins[bin] += Double(acc) / Double(channels)
                    counts[bin] += 1
                }
            }
        }
        guard !bins.isEmpty else { return nil }
        for i in bins.indices where counts[i] > 0 { bins[i] /= Double(counts[i]) }
        return bins
    }

    private static func rate(_ url: URL) async throws -> Double {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { return 30 }
        return Double(max(try await track.load(.nominalFrameRate), 1))
    }

    /// Lag that lines `a` up with `b`: sample i of T against sample i + lag of R.
    private static func slide(_ za: [Double], _ zb: [Double], prior: Int, reach: Int) -> (lag: Int, score: Double)? {
        guard !za.isEmpty, !zb.isEmpty else { return nil }
        let need = max(8, min(za.count, zb.count) / 3)
        var bestLag = prior
        var best = -Double.greatestFiniteMagnitude
        for lag in (prior - reach)...(prior + reach) {
            var sum = 0.0
            var n = 0
            for i in 0..<za.count {
                let j = i + lag
                guard j >= 0, j < zb.count else { continue }
                sum += za[i] * zb[j]
                n += 1
            }
            guard n >= need else { continue }
            let score = sum / Double(n)
            if score > best {
                best = score
                bestLag = lag
            }
        }
        guard best > -Double.greatestFiniteMagnitude / 2 else { return nil }
        return (bestLag, best)
    }

    private static func motion(_ url: URL) async throws -> (curve: [Double], fps: Float) {
        let reader = try await Reader(url: url)
        defer { reader.reader.cancelReading() }
        var curve: [Double] = []
        var last: [UInt8]?
        var more = true
        while more {
            autoreleasepool {
                guard let small = reader.nextGray(width: 96) else {
                    more = false
                    return
                }
                if let last, last.count == small.count {
                    var sum = 0
                    for i in 0..<small.count { sum += abs(Int(small[i]) - Int(last[i])) }
                    curve.append(Double(sum) / Double(small.count))
                } else {
                    curve.append(0)
                }
                last = small
            }
        }
        return (curve, reader.fps)
    }

    private static func zscore(_ v: [Double]) -> [Double] {
        guard v.count > 2 else { return [] }
        let mean = v.reduce(0, +) / Double(v.count)
        let varc = v.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(v.count)
        let sd = varc.squareRoot()
        guard sd > 1e-6 else { return [] }
        return v.map { ($0 - mean) / sd }
    }

    // MARK: - Render

    private static func skip(left: Reader, right: Reader, lag: Int) {
        var tSkip = lag < 0 ? -lag : 0
        var rSkip = lag > 0 ? lag : 0
        while tSkip > 0 {
            let got = autoreleasepool { left.skipOne() }
            guard got else { break }
            tSkip -= 1
        }
        while rSkip > 0 {
            let got = autoreleasepool { right.skipOne() }
            guard got else { break }
            rSkip -= 1
        }
    }

    /// Frames spread across the whole clip. The opening often matches the wrong seam.
    private static func probeIndexes(n: Int) -> [Int] {
        guard n > 16 else { return [max(0, n / 2)] }
        let start = min(12, n / 5)
        let end = max(start, n - 12)
        let steps = min(12, end - start + 1)
        var picks: [Int] = []
        for i in 0..<steps {
            let t = steps == 1 ? 0.0 : Double(i) / Double(steps - 1)
            picks.append(start + Int((Double(end - start) * t).rounded()))
        }
        return Array(Set(picks)).sorted()
    }

    /// One still fit for the whole clip. A false match slides the frames apart and rolls them, so the wider, level seam wins.
    private static func lock(t: URL, r: URL, rig: Rig, lag: Int) async throws -> Hugin.Hold? {
        let left = try await Reader(url: t)
        let right = try await Reader(url: r)
        defer {
            left.reader.cancelReading()
            right.reader.cancelReading()
        }
        skip(left: left, right: right, lag: lag)
        let paired = min(left.frameCount - max(0, -lag), right.frameCount - max(0, lag))
        let calm = probeIndexes(n: max(0, paired))
        let want = Set(calm)
        let last = calm.max() ?? 0
        var best: Hugin.Hold?
        var bestRank = Double.greatestFiniteMagnitude
        var index = 0
        var more = true
        while more && index <= last {
            try autoreleasepool {
                defer { index += 1 }
                guard want.contains(index) else {
                    guard left.skipOne(), right.skipOne() else {
                        more = false
                        return
                    }
                    return
                }
                guard let tImage = left.next(), let rImage = right.next() else {
                    more = false
                    return
                }
                let oriented = rig.flipR ? Stitcher.flop(rImage) : rImage
                guard let found = try Hugin.hold(t: tImage, r: oriented, overlap: rig.overlap(width: tImage.width, height: tImage.height), balance: rig.balance) else { return }
                let wide = found.fit.overlap
                let roll = abs(found.fit.rot)
                let real = roll <= 1.5 && wide >= 0.18
                let rank = (real ? 0.0 : 100.0) - wide * 10 + roll * 0.15
                Trace.line(String(format: "FXPAN video fit frame %d n=%d rot=%+.2f scale=%.4f ol=%.0f%% rank %.3f",
                                  index, found.fit.inliers, found.fit.rot, found.fit.scale, wide * 100, rank))
                if rank < bestRank {
                    bestRank = rank
                    best = found
                }
            }
        }
        if let best {
            Trace.line(String(format: "FXPAN video fit kept n=%d rot=%+.2f ol=%.0f%%",
                              best.fit.inliers, best.fit.rot, best.fit.overlap * 100))
        } else {
            Trace.line("FXPAN video fit missed")
        }
        return best
    }

    private static func render(
        t: URL, r: URL, movie: URL, poster: URL, rig: Rig, lag: Int, hold: Hugin.Hold,
        note: @escaping @Sendable (String) -> Void
    ) async throws -> Made {
        let left = try await Reader(url: t)
        let right = try await Reader(url: r)
        defer {
            left.reader.cancelReading()
            right.reader.cancelReading()
        }
        let fps = max(1, Int(max(left.fps, right.fps).rounded()))
        let total = min(left.frameCount - max(0, -lag), right.frameCount - max(0, lag))
        skip(left: left, right: right, lag: lag)
        var writer: AVAssetWriter?
        var input: AVAssetWriterInput?
        var adaptor: AVAssetWriterInputPixelBufferAdaptor?
        var frames = 0
        var missed = 0
        var size = (w: 0, h: 0)
        let began = CFAbsoluteTimeGetCurrent()
        var more = true
        while more {
            try autoreleasepool {
                guard let tImage = left.next(), let rImage = right.next() else {
                    more = false
                    return
                }
                if frames % 15 == 0 {
                    note(total > 0 ? "Stitching \(frames + 1) of \(total)" : "Stitching \(frames + 1)")
                }
                let oriented = rig.flipR ? Stitcher.flop(rImage) : rImage
                guard var frame = Hugin.frame(t: tImage, r: oriented, hold: hold) else {
                    missed += 1
                    return
                }
                frame = Stitcher.flop(frame)
                let w = frame.width - frame.width % 2
                let h = frame.height - frame.height % 2
                if w < 16 || h < 16 {
                    missed += 1
                    return
                }
                if w != frame.width || h != frame.height, let cropped = frame.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) {
                    frame = cropped
                }
                if writer == nil {
                    size = (w, h)
                    let made = try Self.writer(movie: movie, width: w, height: h)
                    writer = made.0
                    input = made.1
                    adaptor = made.2
                    if let jpg = CGImageDestinationCreateWithURL(poster as CFURL, "public.jpeg" as CFString, 1, nil) {
                        CGImageDestinationAddImage(jpg, frame, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
                        CGImageDestinationFinalize(jpg)
                    }
                }
                guard frame.width == size.w, frame.height == size.h else {
                    missed += 1
                    return
                }
                guard let input, let adaptor, let pool = adaptor.pixelBufferPool else {
                    more = false
                    return
                }
                while !input.isReadyForMoreMediaData {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                var buffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
                guard let buffer else {
                    more = false
                    return
                }
                draw(frame, into: buffer)
                let time = CMTime(value: CMTimeValue(frames), timescale: CMTimeScale(fps))
                guard adaptor.append(buffer, withPresentationTime: time) else {
                    throw PTPError.message(Self.why(writer?.error, fallback: "Could not write a frame"))
                }
                frames += 1
            }
        }
        guard let writer, let input, frames > 0 else { throw PTPError.message("No frames to stitch") }
        input.markAsFinished()
        let gate = DispatchSemaphore(value: 0)
        writer.finishWriting { gate.signal() }
        gate.wait()
        guard writer.status == .completed else {
            throw PTPError.message(Self.why(writer.error, fallback: "Could not write the movie"))
        }
        let blend = hold.useBands ? "multiband" : "feather"
        Trace.line(String(format: "FXPAN video stitched %d frames %dx%d in %.1fs hugin rot=%+.2f ol=%.0f%% missed %d",
                          frames, size.w, size.h, CFAbsoluteTimeGetCurrent() - began, hold.fit.rot, hold.fit.overlap * 100, missed))
        return Made(
            frames: frames, fps: fps, width: size.w, height: size.h,
            overlap: hold.fit.overlap, dy: hold.fit.dy, rot: hold.fit.rot, scale: hold.fit.scale,
            inliers: hold.fit.inliers, blend: blend
        )
    }

    /// Domain and code, because AVFoundation's own text is only "The operation could not be completed".
    private static func why(_ error: Error?, fallback: String) -> String {
        guard let error = error as NSError? else { return fallback }
        let under = (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { " \($0.domain) \($0.code)" } ?? ""
        Trace.line("FXPAN video \(fallback) \(error.domain) \(error.code)\(under)")
        return "\(error.localizedDescription) (\(error.domain) \(error.code)\(under))"
    }

    private static func writer(
        movie: URL, width: Int, height: Int
    ) throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        if FileManager.default.fileExists(atPath: movie.path) {
            try FileManager.default.removeItem(at: movie)
        }
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else {
            throw PTPError.message(Self.why(writer.error, fallback: "Could not start the movie"))
        }
        writer.startSession(atSourceTime: .zero)
        return (writer, input, adaptor)
    }

    /// T's audio goes on after the panorama is finished. Reading it while the frames are still decoding fails the writer.
    private static func attachAudio(from source: URL, to movie: URL, skipFrames: Int, fps: Int) async {
        let picture = AVURLAsset(url: movie)
        let clip = AVURLAsset(url: source)
        guard let vTrack = try? await picture.loadTracks(withMediaType: .video).first,
              let aTrack = try? await clip.loadTracks(withMediaType: .audio).first,
              let vFormat = try? await vTrack.load(.formatDescriptions).first,
              let aDesc = try? await aTrack.load(.formatDescriptions).first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(aDesc)?.pointee else {
            Trace.line("FXPAN video audio none")
            return
        }
        let channels = max(1, min(2, Int(asbd.mChannelsPerFrame)))
        let rate = asbd.mSampleRate > 0 ? asbd.mSampleRate : 48_000
        let out = movie.deletingLastPathComponent().appendingPathComponent("." + movie.lastPathComponent + ".snd")
        try? FileManager.default.removeItem(at: out)
        guard let vReader = try? AVAssetReader(asset: picture),
              let aReader = try? AVAssetReader(asset: clip),
              let writer = try? AVAssetWriter(outputURL: out, fileType: .mov) else { return }
        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: nil)
        vOut.alwaysCopiesSampleData = false
        let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        aOut.alwaysCopiesSampleData = true
        guard vReader.canAdd(vOut), aReader.canAdd(aOut) else { return }
        vReader.add(vOut)
        aReader.add(aOut)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vFormat)
        vIn.expectsMediaDataInRealTime = false
        let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: 160_000,
        ])
        aIn.expectsMediaDataInRealTime = false
        guard writer.canAdd(vIn), writer.canAdd(aIn) else {
            Trace.line("FXPAN video audio writer refused the tracks")
            return
        }
        writer.add(vIn)
        writer.add(aIn)
        guard writer.startWriting(), vReader.startReading(), aReader.startReading() else {
            Trace.line("FXPAN video audio start \(writer.error?.localizedDescription ?? vReader.error?.localizedDescription ?? aReader.error?.localizedDescription ?? "")")
            try? FileManager.default.removeItem(at: out)
            return
        }
        writer.startSession(atSourceTime: .zero)
        let skip = CMTime(value: CMTimeValue(max(0, skipFrames)), timescale: CMTimeScale(max(fps, 1)))
        let lead = CMTime(value: 1, timescale: 2)
        var pending: CMSampleBuffer?
        var videoDone = false
        var audioDone = false
        var videoPTS = CMTime.zero
        while !videoDone || !audioDone {
            var wrote = false
            if !videoDone, vIn.isReadyForMoreMediaData {
                if let sample = vOut.copyNextSampleBuffer() {
                    videoPTS = CMSampleBufferGetPresentationTimeStamp(sample)
                    if !vIn.append(sample) {
                        Trace.line("FXPAN video audio picture \(Self.why(writer.error, fallback: "copy"))")
                        try? FileManager.default.removeItem(at: out)
                        return
                    }
                    wrote = true
                } else {
                    vIn.markAsFinished()
                    videoDone = true
                }
            }
            if !audioDone, aIn.isReadyForMoreMediaData {
                let sample = pending ?? aOut.copyNextSampleBuffer()
                pending = nil
                if let sample {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    if CMTimeCompare(pts, skip) < 0 {
                        wrote = true
                    } else {
                        let shifted = pts - skip
                        if !videoDone, CMTimeCompare(shifted, videoPTS + lead) > 0 {
                            pending = sample
                        } else if let timed = retimed(sample, by: skip), aIn.append(timed) {
                            wrote = true
                        } else {
                            Trace.line("FXPAN video audio buffer \(writer.error?.localizedDescription ?? "")")
                            try? FileManager.default.removeItem(at: out)
                            return
                        }
                    }
                } else {
                    aIn.markAsFinished()
                    audioDone = true
                }
            }
            if !wrote { Thread.sleep(forTimeInterval: 0.005) }
        }
        let gate = DispatchSemaphore(value: 0)
        writer.finishWriting { gate.signal() }
        gate.wait()
        guard writer.status == .completed else {
            Trace.line("FXPAN video audio \(Self.why(writer.error, fallback: "mux"))")
            try? FileManager.default.removeItem(at: out)
            return
        }
        do {
            _ = try FileManager.default.replaceItemAt(movie, withItemAt: out)
            Trace.line("FXPAN video audio kept")
        } catch {
            Trace.line("FXPAN video audio replace \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: out)
        }
    }

    private static func retimed(_ sample: CMSampleBuffer, by skip: CMTime) -> CMSampleBuffer? {
        let count = CMSampleBufferGetNumSamples(sample)
        guard count > 0 else { return nil }
        var infos = [CMSampleTimingInfo](
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: count
        )
        CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &infos, entriesNeededOut: nil)
        for i in 0..<count {
            infos[i].presentationTimeStamp = infos[i].presentationTimeStamp - skip
            if infos[i].decodeTimeStamp.isValid {
                infos[i].decodeTimeStamp = infos[i].decodeTimeStamp - skip
            }
        }
        var copy: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault, sampleBuffer: sample,
            sampleTimingEntryCount: count, sampleTimingArray: &infos, sampleBufferOut: &copy
        )
        return status == noErr ? copy : nil
    }

    private static func draw(_ image: CGImage, into buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: CVPixelBufferGetWidth(buffer),
            height: CVPixelBufferGetHeight(buffer),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    private final class Reader {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let fps: Float
        let frameCount: Int
        private let ci = CIContext(options: [.cacheIntermediates: false])

        init(url: URL) async throws {
            let asset = AVURLAsset(url: url)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                throw PTPError.message("No video track")
            }
            fps = try await track.load(.nominalFrameRate)
            let seconds = try await asset.load(.duration).seconds
            frameCount = seconds.isFinite ? Int((seconds * Double(fps)).rounded()) : 0
            reader = try AVAssetReader(asset: asset)
            output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ])
            output.alwaysCopiesSampleData = false
            reader.add(output)
            guard reader.startReading() else {
                throw PTPError.message(reader.error?.localizedDescription ?? "Could not read the clip")
            }
        }

        /// The image is copied out before the sample buffer is released.
        func next() -> CGImage? {
            guard let sample = output.copyNextSampleBuffer(),
                  let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            return ci.createCGImage(CIImage(cvPixelBuffer: buffer), from: CGRect(x: 0, y: 0, width: w, height: h))
        }

        func skipOne() -> Bool {
            output.copyNextSampleBuffer() != nil
        }

        /// A small gray copy for the motion curve. Scaling happens before the pixels leave the GPU.
        func nextGray(width: Int) -> [UInt8]? {
            guard let sample = output.copyNextSampleBuffer(),
                  let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            guard w > 0, h > 0 else { return [] }
            let s = CGFloat(width) / CGFloat(w)
            let small = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: s, y: s))
            let sh = max(1, Int((CGFloat(h) * s).rounded()))
            guard let cg = ci.createCGImage(small, from: CGRect(x: 0, y: 0, width: width, height: sh)) else { return [] }
            return Stitcher.gray(cg, width: width).pix
        }
    }

    /// Motion stays in the right fifth, which is the overlap after R is flopped.
    private static func clip(to url: URL, delay: Int) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        let width = 640
        let height = 360
        let made = try writer(movie: url, width: width, height: height)
        let cs = CGColorSpaceCreateDeviceRGB()
        let span = width / 5
        let x0 = width - span
        for frame in 0..<24 {
            guard let ctx = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { continue }
            ctx.setFillColor(CGColor(red: 0.12, green: 0.18, blue: 0.16, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            let x = x0 + ((frame + delay) * 10) % max(span - 28, 1)
            ctx.setFillColor(CGColor(red: 0.95, green: 0.75, blue: 0.2, alpha: 1))
            ctx.fill(CGRect(x: x, y: 80, width: 24, height: 200))
            guard let drawn = ctx.makeImage() else { continue }
            while !made.1.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
            var buffer: CVPixelBuffer?
            if let pool = made.2.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            }
            guard let buffer else { continue }
            draw(drawn, into: buffer)
            let time = CMTime(value: CMTimeValue(frame), timescale: 24)
            made.2.append(buffer, withPresentationTime: time)
        }
        made.1.markAsFinished()
        let gate = DispatchSemaphore(value: 0)
        made.0.finishWriting { gate.signal() }
        gate.wait()
    }
}
