import AVFoundation
import CoreGraphics
import ImageIO
import UIKit

/// Line the two D800 clips up in time, fit the overlap once, then stitch every pair the way a still is stitched.
enum PanoVideo {
    /// `gap` is the seconds R started after T, measured when both start commands went out. Nil when it was never measured.
    static func make(
        t: URL, r: URL, movie: URL, poster: URL, rig: Rig, gap: Double?,
        note: @escaping @Sendable (String) -> Void
    ) async throws {
        note("Matching frames")
        let timing = try await Task.detached(priority: .userInitiated) {
            try await offset(t: t, r: r, gap: gap)
        }.value
        let lag = timing.lag
        note("Fitting the overlap")
        let locked = try await Task.detached(priority: .userInitiated) {
            try await lock(t: t, r: r, rig: rig, lag: lag)
        }.value
        note(locked == nil ? "Feathering" : "Stitching")
        let made = try await Task.detached(priority: .userInitiated) {
            try await render(t: t, r: r, movie: movie, poster: poster, rig: rig, lag: lag, locked: locked, note: note)
        }.value
        note("\(made.frames) frames")
        var report = StitchReport(
            overlap: locked?.fit.overlap ?? rig.overlap, overlapPx: 0, dy: locked?.fit.dy ?? 0, flipR: rig.flipR,
            mode: locked == nil ? "video" : "video hugin",
            width: made.width, height: made.height, squeeze: 1, look: "video"
        )
        if let fit = locked?.fit {
            report.rot = fit.rot
            report.scale = fit.scale
            report.inliers = fit.inliers
        }
        let line = lag == 0 ? "in step" : "offset \(lag) frames"
        report.blend = locked.map { "\($0.useBands ? "multiband" : "feather") · \(line)" } ?? line
        report.sec = Double(made.frames) / Double(max(made.fps, 1))
        report.startGap = gap
        report.lag = lag
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
    }

    // MARK: - Timing

    /// T frame i pairs with R frame i + lag. R starting later gives a negative lag, and T skips those frames.
    /// Each clip becomes a motion curve: how much the picture changed since the frame before. Both bodies see the same
    /// movement at the same moment, so the curves line up when the clips do, whatever the exposure or the overlap.
    private static func offset(t: URL, r: URL, gap: Double?) async throws -> (lag: Int, score: Double) {
        let a = try await motion(t)
        let b = try await motion(r)
        let fps = Double(max(a.fps, b.fps, 1))
        let prior = gap.map { Int((-$0 * fps).rounded()) } ?? 0
        let reach = gap == nil ? Int(fps * 6) : Int(fps * 1.5)
        let za = zscore(a.curve)
        let zb = zscore(b.curve)
        let need = max(8, min(za.count, zb.count) / 3)
        var bestLag = prior
        var best = -Double.greatestFiniteMagnitude
        if !za.isEmpty, !zb.isEmpty {
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
        }
        let trusted = best >= 0.25
        let lag = trusted ? bestLag : prior
        Trace.line(String(format: "FXPAN video timing gap %@ prior %d search ±%d best %d corr %.2f use %d",
                          gap.map { String(format: "%+.3fs", $0) } ?? "none", prior, reach, bestLag, best, lag))
        return (lag, best)
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

    // MARK: - Fit

    /// Try the fit on a few matched pairs and keep the one with the most inliers.
    private static func lock(t: URL, r: URL, rig: Rig, lag: Int) async throws -> Hugin.Locked? {
        let left = try await Reader(url: t)
        let right = try await Reader(url: r)
        defer {
            left.reader.cancelReading()
            right.reader.cancelReading()
        }
        skip(left: left, right: right, lag: lag)
        let picks: Set<Int> = [12, 45, 90]
        let last = picks.max() ?? 0
        var best: Hugin.Locked?
        var index = 0
        var more = true
        while more && index <= last {
            try autoreleasepool {
                guard let tImage = left.next(), let rImage = right.next() else {
                    more = false
                    return
                }
                defer { index += 1 }
                guard picks.contains(index) else { return }
                let oriented = rig.flipR ? Stitcher.flop(rImage) : rImage
                let overlap = rig.overlap(width: tImage.width, height: tImage.height)
                guard let found = try Hugin.lock(t: tImage, r: oriented, overlap: overlap, balance: rig.balance) else { return }
                Trace.line(String(format: "FXPAN video fit frame %d n=%d rot=%+.2f scale=%.4f ol=%.0f%% %dx%d",
                                  index, found.fit.inliers, found.fit.rot, found.fit.scale, found.fit.overlap * 100, found.width, found.height))
                if best == nil || found.fit.inliers > best!.fit.inliers { best = found }
            }
        }
        if best == nil { Trace.line("FXPAN video fit missed, feathering the rig overlap") }
        return best
    }

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

    // MARK: - Render

    private static func render(
        t: URL, r: URL, movie: URL, poster: URL, rig: Rig, lag: Int,
        locked: Hugin.Locked?, note: @escaping @Sendable (String) -> Void
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
        var size = (w: 0, h: 0)
        let began = CFAbsoluteTimeGetCurrent()
        var more = true
        while more {
            // Each frame's images, Metal buffers, and sample buffers are freed here, before the next pair is decoded.
            try autoreleasepool {
                guard let tImage = left.next(), let rImage = right.next() else {
                    more = false
                    return
                }
                let stitched: CGImage?
                if let locked {
                    let oriented = rig.flipR ? Stitcher.flop(rImage) : rImage
                    stitched = Hugin.frame(t: tImage, r: oriented, locked: locked)
                        ?? Stitcher.preview(t: tImage, r: rImage, rig: rig, squeeze: 1, maxWidth: tImage.width)
                } else {
                    stitched = Stitcher.preview(t: tImage, r: rImage, rig: rig, squeeze: 1, maxWidth: tImage.width)
                }
                guard var frame = stitched else { return }
                if size.w > 0, frame.width != size.w || frame.height != size.h {
                    frame = Stitcher.sized(frame, to: size.w, height: size.h)
                }
                let w = frame.width - frame.width % 2
                let h = frame.height - frame.height % 2
                if w < 16 || h < 16 { return }
                if w != frame.width || h != frame.height, let cropped = frame.cropping(to: CGRect(x: 0, y: 0, width: w, height: h)) {
                    frame = cropped
                }
                if frames % 15 == 0 {
                    note(total > 0 ? "Stitching \(frames + 1) of \(total)" : "Stitching \(frames + 1)")
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
                    throw PTPError.message(writer?.error?.localizedDescription ?? "Could not write a frame")
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
            throw PTPError.message(writer.error?.localizedDescription ?? "Could not write the movie")
        }
        Trace.line(String(format: "FXPAN video stitched %d frames %dx%d in %.1fs %@",
                          frames, size.w, size.h, CFAbsoluteTimeGetCurrent() - began, locked == nil ? "feather" : "hugin"))
        return Made(frames: frames, fps: fps, width: size.w, height: size.h)
    }

    private static func writer(movie: URL, width: Int, height: Int) throws -> (AVAssetWriter, AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
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
            throw PTPError.message(writer.error?.localizedDescription ?? "Could not start the movie")
        }
        writer.startSession(atSourceTime: .zero)
        return (writer, input, adaptor)
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
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer)))
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
