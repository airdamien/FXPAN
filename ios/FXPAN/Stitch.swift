import CoreGraphics
import CoreImage
import ImageIO
import UIKit
import UniformTypeIdentifiers

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
}

typealias StitchNote = @Sendable (String) -> Void
typealias StitchStop = @Sendable () -> Bool

struct StitchHalt: Error {}

enum StitchGate {
    static func check(_ stop: StitchStop?) throws {
        if stop?() == true || Task.isCancelled { throw StitchHalt() }
    }
}

enum Stitcher {
    static let work = 360

    static func write(tURL: URL, rURL: URL, dest: URL, ana: URL?, rig: Rig, photo: Photo, note: StitchNote? = nil, stop: StitchStop? = nil) throws -> StitchReport {
        try StitchGate.check(stop)
        if photo.drive.engine == "hugin" {
            if let built = try huginFile(tURL: tURL, rURL: rURL, rig: rig, note: note, stop: stop) {
                return try finish(
                    built.image, dest: dest, ana: ana, photo: photo, frameWidth: built.frameWidth,
                    overlap: built.overlap, dy: built.dy, flip: rig.flipR, mode: "hugin", score: nil,
                    rot: built.rot, scale: built.scale, inliers: built.inliers, blend: built.blend, note: note, stop: stop
                )
            }
            note?("Features missed, feathering the seam")
            print("FXPAN hugin SIFT missed — feather")
        }
        note?("Reading the pair")
        guard let tImage = image(at: tURL), let rImage = image(at: rURL) else {
            throw PTPError.message("Could not read the pair")
        }
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
        var oriented = flip ? flop(rImage) : rImage
        if rig.balance { oriented = matched(oriented, to: tImage, overlap: overlap) }
        let mode = photo.drive.engine == "hugin" ? "hugin" : (photo.drive.engine == "cut" ? "cut" : (photo.drive.engine == "match" ? "match" : "blend"))
        note?(mode == "cut" ? "Cutting the seam" : "Blending the seam")
        let cg = paint(t: tImage, r: oriented, overlap: overlap, dy: dy, cut: mode == "cut", clip: photo.frame.clip)
        let blendName = photo.drive.engine == "hugin" ? "feather" : nil
        return try finish(
            cg, dest: dest, ana: ana, photo: photo, frameWidth: frameWidth,
            overlap: overlap, dy: dy, flip: flip, mode: mode, score: score,
            rot: nil, scale: nil, inliers: nil, blend: blendName, note: note, stop: stop
        )
    }

    /// The source frames die with this function, before the blend allocates its pyramids.
    private static func huginFile(tURL: URL, rURL: URL, rig: Rig, note: StitchNote?, stop: StitchStop?) throws -> Hugin.Made? {
        note?("Reading the pair")
        guard let prepared = try preparePair(tURL: tURL, rURL: rURL, rig: rig, note: note, stop: stop) else { return nil }
        return try Hugin.render(prepared, note: note, stop: stop)
    }

    private static func preparePair(tURL: URL, rURL: URL, rig: Rig, note: StitchNote?, stop: StitchStop?) throws -> Hugin.Prepared? {
        guard let tImage = image(at: tURL), let rImage = image(at: rURL) else {
            throw PTPError.message("Could not read the pair")
        }
        let overlap = rig.overlap(width: tImage.width, height: tImage.height)
        let oriented = rig.flipR ? flop(rImage) : rImage
        let balanced = rig.balance ? matched(oriented, to: tImage, overlap: overlap) : oriented
        return try Hugin.prepare(t: tImage, r: balanced, overlap: overlap, frameWidth: tImage.width, note: note, stop: stop)
    }

    private static func finish(
        _ image: CGImage, dest: URL, ana: URL?, photo: Photo, frameWidth: Int,
        overlap: Double, dy: Int, flip: Bool, mode: String, score: Double?,
        rot: Double?, scale: Double?, inliers: Int?, blend: String?, note: StitchNote? = nil, stop: StitchStop? = nil
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
            look: photo.look.base, score: score, rot: rot, scale: scale, inliers: inliers, blend: blend
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

    private static func matched(_ r: CGImage, to t: CGImage, overlap: Double) -> CGImage {
        let tg = gray(t, width: work)
        let rg = gray(r, width: work)
        let ol = max(4, min(tg.w - 1, Int((Double(tg.w) * overlap).rounded())))
        func mean(_ g: Gray, x0: Int, x1: Int) -> Double {
            var sum = 0
            var n = 0
            for y in stride(from: 0, to: g.h, by: 2) {
                for x in x0..<x1 {
                    sum += Int(g.pix[y * g.w + x])
                    n += 1
                }
            }
            return n == 0 ? 0 : Double(sum) / Double(n)
        }
        let tm = mean(tg, x0: 0, x1: ol)
        let rm = mean(rg, x0: rg.w - ol, x1: rg.w)
        guard rm > 4, tm > 4 else { return r }
        let scale = tm / rm
        guard abs(scale - 1) > 0.03, scale >= 0.40, scale <= 2.50 else { return r }
        let ci = CIImage(cgImage: r).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        return ctx.createCGImage(ci, from: ci.extent) ?? r
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
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
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
        let w = image.width
        let h = image.height
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        let ciCtx = CIContext(options: [.workingColorSpace: NSNull(), .cacheIntermediates: false])
        let source = CIImage(cgImage: image)
        let band = 192
        var top = 0
        while top < h {
            autoreleasepool {
                let bh = min(band, h - top)
                let extent = CGRect(x: 0, y: h - top - bh, width: w, height: bh)
                let strip = lookImage(source.cropped(to: extent), look: look)
                if let cg = ciCtx.createCGImage(strip, from: extent) {
                    ctx.draw(cg, in: extent)
                }
            }
            top += band
        }
        return ctx.makeImage() ?? image
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
