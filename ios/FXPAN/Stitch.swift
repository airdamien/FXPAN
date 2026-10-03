import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision

struct StitchReport: Codable {
    var overlap: Double
    var overlapPx: Int
    var dy: Int
    var flipR: Bool
    var mode: String
    var width: Int
    var height: Int
    var squeeze: Double
    var look: String
    var score: Double?
    var rot: Double?
    var scale: Double?
    var inliers: Int?
    var blend: String?
    var sec: Double?
    /// `ciraw` when the pair was developed from the NEFs.
    var develop: String?
}

typealias StitchNote = @Sendable (String) -> Void
typealias StitchStop = @Sendable () -> Bool

struct StitchHalt: Error {}

enum StitchGate {
    static func check(_ stop: StitchStop?) throws {
        if stop?() == true || Task.isCancelled { throw StitchHalt() }
    }
}

/// Apple's raw develop. Orientation stays unrotated so it matches the JPEG the stitch already flops.
enum RawDevelop {
    static func image(at url: URL, lens: Bool) -> CGImage? {
        guard let filter = CIRAWFilter(imageURL: url) else { return nil }
        if #available(iOS 27.0, *) {
            DispatchQueue.global(qos: .userInitiated).sync {
                let wait = DispatchSemaphore(value: 0)
                _ = filter.downloadResources(timeout: 180) { error in
                    if let error { print("FXPAN ciraw decoder \(error.localizedDescription)") }
                    wait.signal()
                }
                wait.wait()
            }
        }
        filter.orientation = .up
        filter.isDraftModeEnabled = false
        filter.scaleFactor = 1
        filter.extendedDynamicRangeAmount = 0
        if #available(iOS 26.0, *) {
            if filter.isHighlightRecoverySupported { filter.isHighlightRecoveryEnabled = true }
        }
        if filter.isLensCorrectionSupported { filter.isLensCorrectionEnabled = lens }
        guard let output = filter.outputImage else { return nil }
        var extent = output.extent.integral
        if extent.isInfinite || extent.isNull || extent.isEmpty {
            extent = CGRect(origin: .zero, size: filter.nativeSize)
        }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CIContext(options: [.cacheIntermediates: false])
        return ctx.createCGImage(output, from: extent, format: .RGBA8, colorSpace: space)
    }
}

enum Stitcher {
    static let work = 360

    static func write(tURL: URL, rURL: URL, dest: URL, ana: URL?, rig: Rig, photo: Photo, note: StitchNote? = nil, stop: StitchStop? = nil) throws -> StitchReport {
        try StitchGate.check(stop)
        if photo.drive.engine == "hugin" {
            if let built = try huginFile(tURL: tURL, rURL: rURL, rig: rig, photo: photo, note: note, stop: stop) {
                return try finish(
                    built.made.image, dest: dest, ana: ana, photo: photo, frameWidth: built.made.frameWidth,
                    overlap: built.made.overlap, dy: built.made.dy, flip: rig.flipR, mode: "hugin", score: nil,
                    rot: built.made.rot, scale: built.made.scale, inliers: built.made.inliers, blend: built.made.blend,
                    develop: built.develop, note: note, stop: stop
                )
            }
            note?("Features missed, feathering the seam")
            print("FXPAN hugin SIFT missed — feather")
        }
        let loaded = try loadPair(tURL: tURL, rURL: rURL, photo: photo, note: note)
        let tImage = loaded.t
        let rImage = loaded.r
        let frameWidth = tImage.width
        let profileOverlap = rig.overlap(width: tImage.width, height: tImage.height)
        var overlap = profileOverlap
        var dy = rig.dy
        var flip = rig.flipR
        var score: Double?
        if photo.drive.engine == "match" {
            note?("Searching the overlap")
            let found = search(t: tImage, r: rImage, profileFlip: rig.flipR)
            score = found.score
            if found.score <= 0.42 {
                overlap = found.overlap
                dy = Int((Double(found.dy) * Double(tImage.width) / Double(work)).rounded())
                flip = found.flip
            }
        }
        var pairT = tImage
        var oriented = flip ? flop(rImage) : rImage
        if rig.balance {
            let pair = matched(oriented, to: pairT, overlap: overlap)
            pairT = pair.t
            oriented = pair.r
        }
        let mode = photo.drive.engine == "hugin" ? "hugin" : (photo.drive.engine == "cut" ? "cut" : (photo.drive.engine == "match" ? "match" : "blend"))
        note?(mode == "cut" ? "Cutting the seam" : "Blending the seam")
        let cg = paint(t: pairT, r: oriented, overlap: overlap, dy: dy, cut: mode == "cut", clip: photo.frame.clip)
        let blendName = photo.drive.engine == "hugin" ? "feather" : nil
        return try finish(
            cg, dest: dest, ana: ana, photo: photo, frameWidth: frameWidth,
            overlap: overlap, dy: dy, flip: flip, mode: mode, score: score,
            rot: nil, scale: nil, inliers: nil, blend: blendName, develop: loaded.develop, note: note, stop: stop
        )
    }

    /// The source frames die with this function, before the blend allocates its pyramids.
    private static func huginFile(tURL: URL, rURL: URL, rig: Rig, photo: Photo, note: StitchNote?, stop: StitchStop?) throws -> (made: Hugin.Made, develop: String?)? {
        let staged = try stage(tURL: tURL, rURL: rURL, rig: rig, photo: photo, note: note, stop: stop)
        guard let prepared = staged.prepared else { return nil }
        let made = try Hugin.render(prepared, note: note, stop: stop)
        return (made, staged.develop)
    }

    /// Develop or read, fit, then drop the source frames before the pyramid.
    private static func stage(tURL: URL, rURL: URL, rig: Rig, photo: Photo, note: StitchNote?, stop: StitchStop?) throws -> (prepared: Hugin.Prepared?, develop: String?) {
        let loaded = try loadPair(tURL: tURL, rURL: rURL, photo: photo, note: note)
        let overlap = rig.overlap(width: loaded.t.width, height: loaded.t.height)
        let oriented = rig.flipR ? flop(loaded.r) : loaded.r
        let prepared = try Hugin.prepare(
            t: loaded.t, r: oriented, overlap: overlap, frameWidth: loaded.t.width,
            balance: rig.balance, note: note, stop: stop
        )
        return (prepared, loaded.develop)
    }

    private static func loadPair(tURL: URL, rURL: URL, photo: Photo, note: StitchNote?) throws -> (t: CGImage, r: CGImage, develop: String?) {
        if photo.drive.ciraw {
            let tNef = tURL.deletingPathExtension().appendingPathExtension("nef")
            let rNef = rURL.deletingPathExtension().appendingPathExtension("nef")
            let files = FileManager.default
            if files.fileExists(atPath: tNef.path), files.fileExists(atPath: rNef.path) {
                note?("Developing T")
                guard let t = RawDevelop.image(at: tNef, lens: photo.drive.cirawLens) else {
                    throw PTPError.message("Could not develop T")
                }
                note?("Developing R")
                guard let r = RawDevelop.image(at: rNef, lens: photo.drive.cirawLens) else {
                    throw PTPError.message("Could not develop R")
                }
                print("FXPAN ciraw \(t.width)x\(t.height) lens \(photo.drive.cirawLens)")
                return (t, r, "ciraw")
            }
            note?("No NEF, using the JPEG")
        }
        note?("Reading the pair")
        guard let t = image(at: tURL), let r = image(at: rURL) else {
            throw PTPError.message("Could not read the pair")
        }
        return (t, r, nil)
    }

    private static func finish(
        _ image: CGImage, dest: URL, ana: URL?, photo: Photo, frameWidth: Int,
        overlap: Double, dy: Int, flip: Bool, mode: String, score: Double?,
        rot: Double?, scale: Double?, inliers: Int?, blend: String?, develop: String? = nil, note: StitchNote? = nil, stop: StitchStop? = nil
    ) throws -> StitchReport {
        try StitchGate.check(stop)
        var cg = image
        if !LookBook.identity(photo.look) {
            note?("Grading the look")
            cg = grade(cg, look: photo.look)
            try StitchGate.check(stop)
        }
        note?("Writing the panorama")
        try jpeg(cg, to: dest)
        if photo.frame.squeeze > 1.01, let ana {
            try StitchGate.check(stop)
            note?("Desqueezing")
            let wide = stretch(cg, squeeze: photo.frame.squeeze)
            try jpeg(wide, to: ana)
        }
        let ol = max(1, min(frameWidth - 1, Int((Double(frameWidth) * overlap).rounded())))
        return StitchReport(
            overlap: overlap, overlapPx: ol, dy: dy, flipR: flip, mode: mode,
            width: cg.width, height: cg.height, squeeze: photo.frame.squeeze,
            look: photo.look.base, score: score, rot: rot, scale: scale, inliers: inliers, blend: blend, develop: develop
        )
    }

    /// Draw the pair with Core Graphics. A Swift loop over a 36 megapixel frame is what left stitch jobs sitting there.
    /// Core Graphics already draws a CGImage upright, so a Y flip here turned the panorama upside down.
    private static func paint(t: CGImage, r: CGImage, overlap: Double, dy: Int, cut: Bool, clip: Bool) -> CGImage {
        let tw = t.width
        let th = t.height
        let ol = max(1, min(tw - 1, Int((Double(tw) * overlap).rounded())))
        let x = tw - ol
        let outW = tw + tw - ol
        let ty = max(0, -dy)
        let ry = max(0, dy)
        let outH = th + abs(dy)
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return t }
        ctx.interpolationQuality = .high
        // User-space origin is the bottom. `ty`/`ry` are pixels down from the top.
        func fromTop(_ offset: Int) -> CGFloat { CGFloat(outH - th - offset) }
        let rRect = CGRect(x: 0, y: fromTop(ry), width: CGFloat(tw), height: CGFloat(th))
        ctx.draw(r, in: rRect)
        let tRect = CGRect(x: CGFloat(x), y: fromTop(ty), width: CGFloat(tw), height: CGFloat(th))
        if cut {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: CGFloat(x + ol / 2), y: fromTop(ty), width: CGFloat(tw - ol / 2), height: CGFloat(th)))
            ctx.draw(t, in: tRect)
            ctx.restoreGState()
        } else {
            ctx.saveGState()
            ctx.clip(to: CGRect(x: CGFloat(x + ol), y: fromTop(ty), width: CGFloat(tw - ol), height: CGFloat(th)))
            ctx.draw(t, in: tRect)
            ctx.restoreGState()
            let slices = 32
            for i in 0..<slices {
                let a0 = Double(i) / Double(slices)
                let a1 = Double(i + 1) / Double(slices)
                let sx = x + Int((a0 * Double(ol)).rounded())
                let ex = x + Int((a1 * Double(ol)).rounded())
                ctx.saveGState()
                ctx.setAlpha((a0 + a1) / 2)
                ctx.clip(to: CGRect(x: CGFloat(sx), y: fromTop(ty), width: CGFloat(max(1, ex - sx)), height: CGFloat(th)))
                ctx.draw(t, in: tRect)
                ctx.restoreGState()
            }
        }
        guard var image = ctx.makeImage() else { return t }
        if clip, dy != 0 {
            let start = max(ty, ry)
            let band = th - abs(dy)
            let cropY = outH - (start + band)
            if band > 8, let cropped = image.cropping(to: CGRect(x: 0, y: cropY, width: outW, height: band)) {
                image = cropped
            }
        }
        return image
    }

    /// Match the overlap by darkening the brighter body, one scale per channel. Scaling up clips highlights.
    private static func matched(_ r: CGImage, to t: CGImage, overlap: Double) -> (t: CGImage, r: CGImage) {
        let width = 480
        let th = max(1, t.height * width / max(1, t.width))
        let tb = bitmap(sized(t, to: width, height: th))
        let rb = bitmap(sized(r, to: width, height: th))
        let ol = max(4, min(tb.w - 1, Int((Double(tb.w) * overlap).rounded())))
        var sumT = [0.0, 0.0, 0.0]
        var sumR = [0.0, 0.0, 0.0]
        var n = 0
        let rows = min(tb.h, rb.h)
        for y in stride(from: 0, to: rows, by: 2) {
            for x in 0..<ol {
                let ti = (y * tb.w + x) * 4
                let ri = (y * rb.w + (rb.w - ol + x)) * 4
                var usable = true
                for c in 0..<3 {
                    if tb.px[ti + c] < 16 || tb.px[ti + c] > 240 || rb.px[ri + c] < 16 || rb.px[ri + c] > 240 {
                        usable = false
                    }
                }
                if !usable { continue }
                for c in 0..<3 {
                    sumT[c] += Double(tb.px[ti + c])
                    sumR[c] += Double(rb.px[ri + c])
                }
                n += 1
            }
        }
        guard n > 40 else { return (t, r) }
        var gT = [1.0, 1.0, 1.0]
        var gR = [1.0, 1.0, 1.0]
        for c in 0..<3 {
            let tm = sumT[c] / Double(n)
            let rm = sumR[c] / Double(n)
            guard rm > 4, tm > 4 else { continue }
            let scale = tm / rm
            guard scale >= 0.40, scale <= 2.50, abs(scale - 1) > 0.008 else { continue }
            if scale < 1 { gR[c] = scale } else { gT[c] = 1 / scale }
        }
        guard gR.contains(where: { $0 < 0.999 }) || gT.contains(where: { $0 < 0.999 }) else { return (t, r) }
        if gR.contains(where: { $0 < 0.999 }) {
            print(String(format: "FXPAN balance R ×%.3f %.3f %.3f", gR[0], gR[1], gR[2]))
        }
        if gT.contains(where: { $0 < 0.999 }) {
            print(String(format: "FXPAN balance T ×%.3f %.3f %.3f", gT[0], gT[1], gT[2]))
        }
        return (scaled(t, by: gT), scaled(r, by: gR))
    }

    private static func scaled(_ image: CGImage, by scale: [Double]) -> CGImage {
        if scale.allSatisfy({ abs($0 - 1) < 0.001 }) { return image }
        let ci = CIImage(cgImage: image).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale[0], y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale[1], z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale[2], w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        return ctx.createCGImage(ci, from: ci.extent) ?? image
    }

    static func preview(t: CGImage, r: CGImage, rig: Rig, squeeze: Double, maxWidth: Int) -> CGImage? {
        let scale = min(1, Double(maxWidth) / Double(t.width))
        let tw = max(16, Int((Double(t.width) * scale).rounded()))
        let th = max(16, Int((Double(t.height) * scale).rounded()))
        let ts = sized(t, to: tw, height: th)
        let rs = sized(rig.flipR ? flop(r) : r, to: tw, height: th)
        let out = compose(t: bitmap(ts), r: bitmap(rs), overlap: rig.overlap(width: t.width, height: t.height), dy: 0, cut: false)
        var cg = out.bitmap.image()
        if squeeze > 1.01 { cg = stretch(cg, squeeze: squeeze) }
        return cg
    }

    // MARK: - Match

    struct Align {
        var score: Double
        var overlap: Double
        var dy: Int
        var flip: Bool
    }

    static func search(t: CGImage, r: CGImage, profileFlip: Bool) -> Align {
        let tg = gray(t, width: work)
        var best: Align?
        for flip in [false, true] {
            let src = flip ? flop(r) : r
            let rg = gray(src, width: work)
            let row = searchShift(t: tg, r: rg)
            let align = Align(score: row.0, overlap: row.1, dy: row.2, flip: flip)
            if best == nil {
                best = align
            } else if let have = best {
                if flip && align.score < have.score * 0.92 { best = align }
                else if !flip && align.score <= have.score { best = align }
            }
        }
        return best ?? Align(score: 1e9, overlap: 0.20, dy: 0, flip: profileFlip)
    }

    private static func searchShift(t: Gray, r: Gray) -> (Double, Double, Int) {
        let maxDy = min(8, t.h / 24)
        var best = (1e9, 0.20, 0)
        for pct in stride(from: 10, to: 43, by: 3) {
            let ol = max(4, Int((Double(t.w) * Double(pct) / 100).rounded()))
            let step = maxDy == 0 ? 1 : 2
            var dy = -maxDy
            while dy <= maxDy {
                let s = score(t, r, ol: ol, dy: dy)
                if s < best.0 { best = (s, Double(pct) / 100, dy) }
                dy += step
            }
        }
        let pct0 = Int((best.1 * 100).rounded())
        let dy0 = best.2
        for pct in max(10, pct0 - 3)...min(43, pct0 + 3) {
            let ol = max(4, Int((Double(t.w) * Double(pct) / 100).rounded()))
            for dy in max(-maxDy, dy0 - 3)...min(maxDy, dy0 + 3) {
                let s = score(t, r, ol: ol, dy: dy)
                if s < best.0 { best = (s, Double(pct) / 100, dy) }
            }
        }
        return best
    }

    private static func score(_ t: Gray, _ r: Gray, ol: Int, dy: Int) -> Double {
        let y0t = max(0, -dy)
        let y0r = max(0, dy)
        let rows = min(t.h - y0t, r.h - y0r)
        if rows < 8 || ol < 4 || ol >= t.w || ol >= r.w { return 1e9 }
        let xr = r.w - ol
        let i0 = Int(Double(rows) * 0.22)
        let i1 = max(i0 + 8, Int(Double(rows) * 0.78))
        var sumt = 0, sumr = 0, sumt2 = 0, sumr2 = 0, sumtr = 0
        for i in i0..<i1 {
            let toff = (y0t + i) * t.w
            let roff = (y0r + i) * r.w + xr
            for x in 0..<ol {
                let tv = Int(t.pix[toff + x])
                let rv = Int(r.pix[roff + x])
                sumt += tv
                sumr += rv
                sumt2 += tv * tv
                sumr2 += rv * rv
                sumtr += tv * rv
            }
        }
        let n = Double((i1 - i0) * ol)
        let mt = Double(sumt) / n
        let mr = Double(sumr) / n
        let vt = Double(sumt2) / n - mt * mt
        let vr = Double(sumr2) / n - mr * mr
        if vt < 8 || vr < 8 { return 1e9 }
        let ncc = (Double(sumtr) / n - mt * mr) / (vt * vr).squareRoot()
        let frac = Double(ol) / Double(t.w)
        return (1 - ncc) + 0.004 * Double(abs(dy)) + 0.10 * abs(frac - 0.20)
    }

    // MARK: - Pixels

    struct Bitmap {
        var w: Int
        var h: Int
        var px: [UInt8]

        func image() -> CGImage {
            let cs = CGColorSpaceCreateDeviceRGB()
            let data = Data(px) as CFData
            let provider = CGDataProvider(data: data)!
            return CGImage(
                width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )!
        }
    }

    struct Composed {
        var bitmap: Bitmap
        var overlapPx: Int
    }

    struct Gray {
        var w: Int
        var h: Int
        var pix: [UInt8]
    }

    static func compose(t: Bitmap, r: Bitmap, overlap: Double, dy: Int, cut: Bool) -> Composed {
        let ol = max(1, min(t.w - 1, Int((Double(t.w) * overlap).rounded())))
        let x = t.w - ol
        let outW = t.w + t.w - ol
        let ty = max(0, -dy)
        let ry = max(0, dy)
        let outH = t.h + abs(dy)
        var px = [UInt8](repeating: 0, count: outW * outH * 4)
        func put(_ src: Bitmap, _ ox: Int, _ oy: Int) {
            for row in 0..<src.h {
                let dy0 = oy + row
                if dy0 < 0 || dy0 >= outH { continue }
                for col in 0..<src.w {
                    let dx0 = ox + col
                    if dx0 < 0 || dx0 >= outW { continue }
                    let s = (row * src.w + col) * 4
                    let d = (dy0 * outW + dx0) * 4
                    px[d] = src.px[s]
                    px[d + 1] = src.px[s + 1]
                    px[d + 2] = src.px[s + 2]
                    px[d + 3] = 255
                }
            }
        }
        put(r, 0, ry)
        put(t, x, ty)
        if cut {
            let seam = ol / 2
            for row in 0..<min(t.h, r.h) - abs(ty - ry) {
                let y = max(ty, ry) + row
                for local in 0..<ol {
                    let useT = local >= seam
                    let src = useT ? t : r
                    let sx = useT ? local : (r.w - ol + local)
                    let sy = useT ? (y - ty) : (y - ry)
                    if sy < 0 || sy >= src.h || sx < 0 || sx >= src.w { continue }
                    let s = (sy * src.w + sx) * 4
                    let d = (y * outW + (x + local)) * 4
                    px[d] = src.px[s]
                    px[d + 1] = src.px[s + 1]
                    px[d + 2] = src.px[s + 2]
                    px[d + 3] = 255
                }
            }
        } else if ol > 1 {
            let y0 = max(ty, ry)
            let rows = min(t.h, r.h) - abs(ty - ry)
            for row in 0..<max(0, rows) {
                let y = y0 + row
                let tsy = y - ty
                let rsy = y - ry
                for local in 0..<ol {
                    let a = Double(local) / Double(ol - 1)
                    let ts = (tsy * t.w + local) * 4
                    let rs = (rsy * r.w + (r.w - ol + local)) * 4
                    let d = (y * outW + (x + local)) * 4
                    for c in 0..<3 {
                        let rv = Double(r.px[rs + c])
                        let tv = Double(t.px[ts + c])
                        px[d + c] = UInt8(min(255, max(0, rv * (1 - a) + tv * a)).rounded())
                    }
                    px[d + 3] = 255
                }
            }
        }
        return Composed(bitmap: Bitmap(w: outW, h: outH, px: px), overlapPx: ol)
    }

    static func balance(_ r: Bitmap, to t: Bitmap, overlap: Double) -> Bitmap {
        let ol = max(1, min(t.w - 1, Int((Double(t.w) * overlap).rounded())))
        let tm = mean(t, x0: 0, x1: ol)
        let rm = mean(r, x0: r.w - ol, x1: r.w)
        if rm <= 0.02 || tm <= 0.02 { return r }
        let scale = tm / rm
        if abs(scale - 1) <= 0.03 || scale < 0.40 || scale > 2.50 { return r }
        var out = r
        for i in stride(from: 0, to: out.px.count, by: 4) {
            for c in 0..<3 {
                out.px[i + c] = UInt8(min(255, max(0, (Double(out.px[i + c]) * scale).rounded())))
            }
        }
        return out
    }

    private static func mean(_ b: Bitmap, x0: Int, x1: Int) -> Double {
        var sum = 0.0
        var n = 0
        let a = max(0, x0)
        let z = min(b.w, x1)
        for y in 0..<b.h {
            for x in a..<z {
                let i = (y * b.w + x) * 4
                sum += (Double(b.px[i]) + Double(b.px[i + 1]) + Double(b.px[i + 2])) / (3 * 255)
                n += 1
            }
        }
        return n == 0 ? 0 : sum / Double(n)
    }

    private static func cropBars(_ composed: Composed, dy: Int) -> Composed {
        let b = composed.bitmap
        let y0 = abs(dy)
        let h = b.h - y0
        guard h > 8, y0 > 0 else { return composed }
        var px = [UInt8](repeating: 0, count: b.w * h * 4)
        for y in 0..<h {
            let s = ((y0 + y) * b.w) * 4
            let d = (y * b.w) * 4
            px.replaceSubrange(d..<(d + b.w * 4), with: b.px[s..<(s + b.w * 4)])
        }
        return Composed(bitmap: Bitmap(w: b.w, h: h, px: px), overlapPx: composed.overlapPx)
    }

    // MARK: - CG

    static func image(at url: URL) -> CGImage? {
        let opts = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let src = CGImageSourceCreateWithURL(url as CFURL, opts) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, opts)
    }

    static func thumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) else { return nil }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }

    static func flop(_ image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.translateBy(x: CGFloat(w), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func sized(_ image: CGImage, to w: Int, height h: Int) -> CGImage {
        if image.width == w && image.height == h { return image }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    static func bitmap(_ image: CGImage) -> Bitmap {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return Bitmap(w: w, h: h, px: px)
    }

    static func gray(_ image: CGImage, width: Int) -> Gray {
        let h = max(1, Int((Double(image.height) * Double(width) / Double(image.width)).rounded()))
        var pix = [UInt8](repeating: 0, count: width * h)
        let cs = CGColorSpaceCreateDeviceGray()
        pix.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: width, height: h, bitsPerComponent: 8, bytesPerRow: width,
                space: cs, bitmapInfo: 0
            ) else { return }
            ctx.interpolationQuality = .low
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: h))
        }
        return Gray(w: width, h: h, pix: pix)
    }

    static func stretch(_ image: CGImage, squeeze: Double) -> CGImage {
        let w = max(1, Int((Double(image.width) * squeeze).rounded()))
        return sized(image, to: w, height: image.height)
    }

    static func jpeg(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PTPError.message("Could not write JPEG")
        }
        let props = [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary
        CGImageDestinationAddImage(dest, image, props)
        if !CGImageDestinationFinalize(dest) {
            throw PTPError.message("Could not write JPEG")
        }
    }

    static func grade(_ image: CGImage, look: LookSet) -> CGImage {
        let image = vision(image, effect: look.apple)
        let w = image.width
        let h = image.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        let ciCtx = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        let prepared = apple(CIImage(cgImage: image), effect: look.apple)
        let band = 192
        var top = 0
        while top < h {
            autoreleasepool {
                let bh = min(band, h - top)
                let extent = CGRect(x: 0, y: h - top - bh, width: w, height: bh)
                let strip = lookImage(prepared.cropped(to: extent), look: look)
                if let cg = ciCtx.createCGImage(strip, from: extent) {
                    ctx.draw(cg, in: extent)
                }
            }
            top += band
        }
        return ctx.makeImage() ?? image
    }

    /// Subject and people masks run before the strip grade. No instance means the frame stays as it was.
    private static func vision(_ image: CGImage, effect: String) -> CGImage {
        let request: VNImageBasedRequest?
        switch effect {
        case "subject": request = VNGenerateForegroundInstanceMaskRequest()
        case "people": request = VNGeneratePersonInstanceMaskRequest()
        default: request = nil
        }
        guard let request else { return image }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first as? VNInstanceMaskObservation,
              obs.allInstances.count > 0,
              let buffer = try? obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false) else {
            return image
        }
        let cut = CIImage(cvPixelBuffer: buffer)
        let ciCtx = CIContext(options: [.workingColorSpace: NSNull()])
        guard let subject = ciCtx.createCGImage(cut, from: cut.extent) else { return image }
        let w = image.width
        let h = image.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        ctx.draw(image, in: rect)
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 0.55)
        ctx.fill(rect)
        ctx.draw(subject, in: rect)
        return ctx.makeImage() ?? image
    }

    /// Applied on the whole frame, then cropped into strips. Vignette, bloom, and sharpen need the full extent.
    private static func apple(_ source: CIImage, effect: String) -> CIImage {
        guard let item = AppleBook.effect(effect) else { return source }
        let short = min(source.extent.width, source.extent.height)
        switch item.id {
        case "subject", "people":
            return source
        case "sharpen":
            return source.applyingFilter(item.filter, parameters: [kCIInputSharpnessKey: 0.7])
        case "unsharp":
            return source.applyingFilter(item.filter, parameters: [
                kCIInputRadiusKey: max(1.5, short * 0.0018),
                kCIInputIntensityKey: 0.7,
            ])
        case "denoise":
            return source.applyingFilter(item.filter, parameters: ["inputNoiseLevel": 0.03, "inputSharpness": 0.45])
        case "bloom":
            return source.applyingFilter(item.filter, parameters: [
                kCIInputRadiusKey: max(4, short * 0.012),
                kCIInputIntensityKey: 0.55,
            ])
        case "vignette":
            return source.applyingFilter(item.filter, parameters: [kCIInputIntensityKey: 0.85, "inputRadius": 1.5])
        case "recover":
            return source.applyingFilter(item.filter, parameters: ["inputHighlightAmount": 0.45, "inputShadowAmount": 0.4])
        case "vibrance":
            return source.applyingFilter(item.filter, parameters: [kCIInputAmountKey: 0.8])
        case "warm":
            return source.applyingFilter(item.filter, parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 4800, y: 8),
            ])
        case "cool":
            return source.applyingFilter(item.filter, parameters: [
                "inputNeutral": CIVector(x: 6500, y: 0),
                "inputTargetNeutral": CIVector(x: 9000, y: -6),
            ])
        default:
            return source.applyingFilter(item.filter)
        }
    }

    /// Point filters only, so a strip grades the same as the whole frame. Grain stays inside the strip instead of allocating a full-frame noise image.
    private static func lookImage(_ source: CIImage, look: LookSet) -> CIImage {
        let base = LookBook.base(look.base)
        var ci = source
        if base.mono {
            let m = LookBook.mix(look.filter)
            ci = ci.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: m.0, y: m.1, z: m.2, w: 0),
                "inputGVector": CIVector(x: m.0, y: m.1, z: m.2, w: 0),
                "inputBVector": CIVector(x: m.0, y: m.1, z: m.2, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            ])
        } else {
            let sat = max(0, base.sat * (1 + 0.12 * Double(look.color)))
            if abs(sat - 1) > 0.01 {
                ci = ci.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: sat])
            }
            if let g = base.gain {
                ci = ci.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: g.0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: g.1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: g.2, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                ])
            }
        }
        let (shadow, high) = LookBook.amounts(look)
        if abs(shadow) > 0.01 || abs(high) > 0.01 {
            var points: [String: CIVector] = [:]
            for i in 0..<5 {
                let x = Double(i) / 4
                let y = LookBook.curve(x, shadow: shadow, high: high)
                points["inputPoint\(i)"] = CIVector(x: x, y: y)
            }
            ci = ci.applyingFilter("CIToneCurve", parameters: points)
        }
        let grain = look.grain == "strong" ? 0.34 : (look.grain == "weak" ? 0.18 : 0)
        if grain > 0 {
            let noise = CIFilter(name: "CIRandomGenerator")!.outputImage!
                .cropped(to: ci.extent)
                .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
            let faded = noise.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: grain),
            ])
            ci = faded.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: ci])
        }
        return ci
    }
}
