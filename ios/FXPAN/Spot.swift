import Accelerate
import Foundation

/// The overlap is the same subject on both legs of one lens. The soft leg is the sharp leg seen through a wider blur and a contrast veil.
/// Both are measured in the overlap, then undone across the whole soft leg with a total-variation deconvolution. The soft pixels stay the data and its grain is put back as shot.
enum Spot {
    enum Result {
        /// The softer leg was restored toward the sharper one.
        case restored(Fit)
        /// The two legs are already within a tenth of each other.
        case same
        /// This leg is the sharper one.
        case skipped
        /// The overlap did not yield a blur.
        case missed
    }

    struct Fit {
        var sx: Float
        var sy: Float
        /// Restored overlap detail divided by the sharper leg's detail. 1 is a match.
        var reached: Float
        /// Which leg was brought up. The sharper leg is left as shot.
        var leg: String = ""
    }

    private struct Box {
        var x0: Int
        var x1: Int
        var y0: Int
        var y1: Int
        var width: Int { x1 - x0 }
        var height: Int { y1 - y0 }
    }

    private struct Blur {
        var sigma: Float
        /// soft ≈ gain · blurred sharp + offset, in luma.
        var gain: Float
        var offset: Float
    }

    /// Measures both legs in the overlap, then brings the softer one up to the sharper one. The sharper leg is not touched.
    static func match(r: inout [UInt8], t: inout [UInt8], w: Int, h: Int, note: ((String) -> Void)? = nil) -> Result {
        guard w > 32, h > 32, r.count == w * h * 4, t.count == r.count else { return .missed }
        guard let box = overlap(r, t, w, h) else { return .missed }
        let er = energy(r, w, box, lag: 2)
        let et = energy(t, w, box, lag: 2)
        Trace.line(String(format: "FXPAN spot measure T %.2f R %.2f", et, er))
        guard max(er, et) > 2 else { return .missed }
        if min(er, et) >= max(er, et) * 0.9 { return .same }
        let tSofter = et < er
        Trace.line(tSofter ? "FXPAN spot R sharper, matching T" : "FXPAN spot T sharper, matching R")
        note?(tSofter ? "Restoring T" : "Restoring R")
        var result = tSofter ? restore(soft: &t, sharp: r, w: w, h: h, box: box) : restore(soft: &r, sharp: t, w: w, h: h, box: box)
        if case .restored(var fit) = result {
            fit.leg = tSofter ? "T" : "R"
            result = .restored(fit)
        }
        return result
    }

    private static func restore(soft: inout [UInt8], sharp: [UInt8], w: Int, h: Int, box: Box) -> Result {
        guard let blur = fit(sharp: sharp, soft: soft, w: w, box: box) else { return .missed }
        guard blur.sigma >= 2 else {
            Trace.line(String(format: "FXPAN spot blur σ %.1f, already close", blur.sigma))
            return .same
        }
        let start = Date()
        guard deblur(&soft, w: w, h: h, blur: blur) else { return .missed }
        let reached = energy(soft, w, box, lag: 4) / max(energy(sharp, w, box, lag: 4), 0.5)
        Trace.line(String(format: "FXPAN spot σ %.1f gain %.2f offset %+.0f  %.0f%%  %.1fs",
                          blur.sigma, blur.gain, blur.offset, reached * 100, Date().timeIntervalSince(start)))
        return .restored(Fit(sx: blur.sigma, sy: blur.sigma, reached: reached))
    }

    private static func overlap(_ a: [UInt8], _ b: [UInt8], _ w: Int, _ h: Int) -> Box? {
        var x0 = w, x1 = 0, y0 = h, y1 = 0, n = 0
        var y = 0
        while y < h {
            let row = y * w
            var x = 0
            while x < w {
                let i = (row + x) * 4
                if a[i + 3] > 32, b[i + 3] > 32 {
                    if x < x0 { x0 = x }
                    if x > x1 { x1 = x }
                    if y < y0 { y0 = y }
                    if y > y1 { y1 = y }
                    n += 1
                }
                x += 4
            }
            y += 4
        }
        guard n > 400, x1 - x0 > 48, y1 - y0 > 48 else { return nil }
        return Box(x0: x0, x1: x1 + 1, y0: y0, y1: y1 + 1)
    }

    /// Mean absolute difference at `lag` pixels.
    private static func energy(_ px: [UInt8], _ w: Int, _ box: Box, lag: Int) -> Float {
        let step = max(1, lag)
        var acc: Float = 0
        var n: Float = 0
        var y = box.y0
        while y + step < box.y1 {
            let row = y * w
            var x = box.x0
            while x + step < box.x1 {
                let i = (row + x) * 4
                let j = (row + x + step) * 4
                let k = ((y + step) * w + x) * 4
                if px[i + 3] > 32, px[j + 3] > 32, px[k + 3] > 32 {
                    let c = luma(px, i)
                    acc += abs(c - luma(px, j)) + abs(c - luma(px, k))
                    n += 2
                }
                x += step
            }
            y += step
        }
        return n > 0 ? acc / n : 0
    }

    /// The blur and veil that turn the sharp overlap into the soft one. Both sides are smoothed first so grain does not favor a wide blur.
    private static func fit(sharp: [UInt8], soft: [UInt8], w: Int, box: Box) -> Blur? {
        let cw = min(384, box.width)
        let ch = min(384, box.height)
        guard cw > 64, ch > 64 else { return nil }
        let ox = box.x0 + (box.width - cw) / 2
        let oy = box.y0 + (box.height - ch) / 2
        var guide = [Float](repeating: 0, count: cw * ch)
        var seen = [Float](repeating: 0, count: cw * ch)
        var ok = [Bool](repeating: false, count: cw * ch)
        var nOk = 0
        for y in 0..<ch {
            for x in 0..<cw {
                let i = ((oy + y) * w + ox + x) * 4
                guard sharp[i + 3] > 32, soft[i + 3] > 32 else { continue }
                let o = y * cw + x
                guide[o] = luma(sharp, i)
                seen[o] = luma(soft, i)
                ok[o] = true
                nOk += 1
            }
        }
        guard nOk > cw * ch / 2 else { return nil }
        fill(&guide, ok, cw, ch)
        fill(&seen, ok, cw, ch)
        let g2 = gauss(guide, cw, ch, 2, 2)
        let s2 = gauss(seen, cw, ch, 2, 2)
        let shifted = align(g2, s2, ok, cw, ch)
        let margin = 40
        var use = ok
        for y in 0..<ch {
            for x in 0..<cw where x < margin || y < margin || x >= cw - margin || y >= ch - margin {
                use[y * cw + x] = false
            }
        }
        func fitted(_ b: [Float]) -> (err: Float, gain: Float, offset: Float) {
            var sb: Float = 0, ss: Float = 0, sbb: Float = 0, sbs: Float = 0, n: Float = 0
            for i in use.indices where use[i] {
                sb += b[i]; ss += s2[i]; sbb += b[i] * b[i]; sbs += b[i] * s2[i]; n += 1
            }
            guard n > 100 else { return (1e9, 1, 0) }
            let den = n * sbb - sb * sb
            let gain = den > 1e-3 ? (n * sbs - sb * ss) / den : 1
            let offset = (ss - gain * sb) / n
            var err: Float = 0
            for i in use.indices where use[i] {
                let d = gain * b[i] + offset - s2[i]
                err += d * d
            }
            return (err / n, gain, offset)
        }
        let plain = fitted(shifted)
        var best = plain
        var pick: Float = 0
        for sigma: Float in [1.5, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14] {
            let f = fitted(gauss(shifted, cw, ch, sigma, sigma))
            if f.err < best.err {
                best = f
                pick = sigma
            }
        }
        guard pick > 0, best.gain > 0.3, best.gain < 2 else {
            Trace.line(String(format: "FXPAN spot no blur fit, mse %.1f vs plain %.1f gain %.2f", best.err, plain.err, best.gain))
            return nil
        }
        Trace.line(String(format: "FXPAN spot fit σ %.1f gain %.2f offset %+.1f mse %.0f%% of plain", pick, best.gain, best.offset, best.err / max(plain.err, 1e-3) * 100))
        return Blur(sigma: pick, gain: best.gain, offset: best.offset)
    }

    /// Leftover seam shift, found on smoothed copies so the blur does not pull it.
    private static func align(_ guide: [Float], _ seen: [Float], _ ok: [Bool], _ w: Int, _ h: Int) -> [Float] {
        let soft = gauss(guide, w, h, 4, 4)
        var mg: Float = 0, ms: Float = 0, n: Float = 0
        for i in ok.indices where ok[i] { mg += soft[i]; ms += seen[i]; n += 1 }
        mg /= max(n, 1); ms /= max(n, 1)
        func miss(_ dx: Int, _ dy: Int) -> Float {
            var acc: Float = 0
            var cnt: Float = 0
            for y in stride(from: 20, to: h - 20, by: 2) {
                for x in stride(from: 20, to: w - 20, by: 2) {
                    let i = y * w + x
                    guard ok[i] else { continue }
                    let xs = min(w - 1, max(0, x - dx))
                    let ys = min(h - 1, max(0, y - dy))
                    let d = (soft[ys * w + xs] - mg) - (seen[i] - ms)
                    acc += d * d
                    cnt += 1
                }
            }
            return cnt > 0 ? acc / cnt : 1e9
        }
        var best = miss(0, 0)
        var pick = (0, 0)
        for dy in stride(from: -16, through: 16, by: 2) {
            for dx in stride(from: -16, through: 16, by: 2) {
                let err = miss(dx, dy)
                if err < best { best = err; pick = (dx, dy) }
            }
        }
        let (cx, cy) = pick
        for dy in (cy - 1)...(cy + 1) {
            for dx in (cx - 1)...(cx + 1) {
                let err = miss(dx, dy)
                if err < best { best = err; pick = (dx, dy) }
            }
        }
        guard pick != (0, 0) else { return guide }
        var out = guide
        for y in 0..<h {
            for x in 0..<w {
                let xs = min(w - 1, max(0, x - pick.0))
                let ys = min(h - 1, max(0, y - pick.1))
                out[y * w + x] = guide[ys * w + xs]
            }
        }
        return out
    }

    private static func luma(_ px: [UInt8], _ i: Int) -> Float {
        0.30 * Float(px[i]) + 0.59 * Float(px[i + 1]) + 0.11 * Float(px[i + 2])
    }

    private static func fill(_ px: inout [Float], _ ok: [Bool], _ w: Int, _ h: Int) {
        for y in 0..<h {
            var carry: Float = 0
            var have = false
            let row = y * w
            for x in 0..<w {
                let i = row + x
                if ok[i] {
                    carry = px[i]
                    have = true
                } else if have {
                    px[i] = carry
                }
            }
            have = false
            var x = w - 1
            while x >= 0 {
                let i = row + x
                if ok[i] {
                    carry = px[i]
                    have = true
                } else if have {
                    px[i] = carry
                }
                x -= 1
            }
        }
    }

    private static func gauss(_ src: [Float], _ w: Int, _ h: Int, _ sx: Float, _ sy: Float) -> [Float] {
        let kx = weights(sx)
        let ky = weights(sy)
        var mid = [Float](repeating: 0, count: w * h)
        var out = [Float](repeating: 0, count: w * h)
        kx.withUnsafeBufferPointer { hx in
            ky.withUnsafeBufferPointer { hy in
                guard let bx = hx.baseAddress, let by = hy.baseAddress else { return }
                blur(src, &mid, &out, w, h, bx, by, UInt32(kx.count), UInt32(ky.count))
            }
        }
        return out
    }

    private static func weights(_ sigma: Float) -> [Float] {
        let s = max(sigma, 0.4)
        let rad = max(1, Int(ceil(s * 3)))
        var k = [Float](repeating: 0, count: rad * 2 + 1)
        var sum: Float = 0
        for i in 0..<k.count {
            let d = Float(i - rad)
            let v = exp(-0.5 * d * d / (s * s))
            k[i] = v
            sum += v
        }
        for i in k.indices { k[i] /= sum }
        return k
    }

    private static func blur(
        _ src: [Float], _ mid: inout [Float], _ dst: inout [Float],
        _ w: Int, _ h: Int,
        _ hx: UnsafePointer<Float>, _ hy: UnsafePointer<Float>,
        _ nx: UInt32, _ ny: UInt32
    ) {
        let rowBytes = w * MemoryLayout<Float>.stride
        let flags = vImage_Flags(kvImageEdgeExtend)
        src.withUnsafeBufferPointer { s in
            mid.withUnsafeMutableBufferPointer { m in
                dst.withUnsafeMutableBufferPointer { d in
                    var sb = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: s.baseAddress), height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
                    var mb = vImage_Buffer(data: m.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
                    var db = vImage_Buffer(data: d.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: rowBytes)
                    _ = vImageConvolve_PlanarF(&sb, &mb, nil, 0, 0, hx, 1, nx, 0, flags)
                    _ = vImageConvolve_PlanarF(&mb, &db, nil, 0, 0, hy, ny, 1, 0, flags)
                }
            }
        }
    }

    /// Luma is smoothed by one pixel, deconvolved, then detail is lifted by the veil around its local mean so tones stay as shot. The grain that was smoothed off is added back unboosted.
    private static func deblur(_ px: inout [UInt8], w: Int, h: Int, blur: Blur) -> Bool {
        var x0 = w, x1 = 0, y0 = h, y1 = 0
        for y in stride(from: 0, to: h, by: 2) {
            let row = y * w
            for x in stride(from: 0, to: w, by: 2) where px[(row + x) * 4 + 3] > 32 {
                if x < x0 { x0 = x }
                if x > x1 { x1 = x }
                if y < y0 { y0 = y }
                if y > y1 { y1 = y }
            }
        }
        guard x1 > x0 + 64, y1 > y0 + 64 else { return false }
        x0 = max(0, x0 - 2); y0 = max(0, y0 - 2)
        x1 = min(w - 1, x1 + 2); y1 = min(h - 1, y1 + 2)
        let bw = x1 - x0 + 1
        let bh = y1 - y0 + 1
        var plane = [Float](repeating: 0, count: bw * bh)
        var ok = [Bool](repeating: false, count: bw * bh)
        var rowHas = [Bool](repeating: false, count: bh)
        for y in 0..<bh {
            for x in 0..<bw {
                let i = ((y0 + y) * w + x0 + x) * 4
                if px[i + 3] > 32 {
                    plane[y * bw + x] = luma(px, i)
                    ok[y * bw + x] = true
                    rowHas[y] = true
                }
            }
        }
        fill(&plane, ok, bw, bh)
        if let first = rowHas.firstIndex(of: true), let last = rowHas.lastIndex(of: true) {
            var near = first
            for y in 0..<bh {
                if rowHas[y] { near = y; continue }
                let src = y < first ? first : (y > last ? last : near)
                for x in 0..<bw { plane[y * bw + x] = plane[src * bw + x] }
            }
        }
        let smooth = gauss(plane, bw, bh, 1, 1)
        guard let sharp = deconvolve(smooth, bw, bh, sigma: blur.sigma) else { return false }
        let gain = min(1, max(0.6, blur.gain))
        let spread = min(40, blur.sigma * 3)
        let base = gauss(sharp, bw, bh, spread, spread)
        for y in 0..<bh {
            for x in 0..<bw {
                let o = y * bw + x
                guard ok[o] else { continue }
                let unveiled = base[o] + (sharp[o] - base[o]) / gain
                let target = unveiled + (plane[o] - smooth[o])
                let d = target - plane[o]
                let i = ((y0 + y) * w + x0 + x) * 4
                for c in 0..<3 {
                    let v = Float(px[i + c]) + d
                    px[i + c] = UInt8(min(255, max(0, v.rounded())))
                }
            }
        }
        return true
    }

    /// One FFT plan per thread. A plan is not safe to share, and the tiles were queued on a single plan.
    private final class FFTKeep: NSObject {
        let setup: FFTSetup
        init(_ log2n: vDSP_Length) {
            setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
            super.init()
        }
        deinit { vDSP_destroy_fftsetup(setup) }
    }

    private static func fftSetup(_ log2n: vDSP_Length) -> FFTSetup {
        let key = "fxpan.fft.\(log2n)"
        if let keep = Thread.current.threadDictionary[key] as? FFTKeep { return keep.setup }
        let keep = FFTKeep(log2n)
        Thread.current.threadDictionary[key] = keep
        return keep.setup
    }

    /// Total-variation deconvolution by half-quadratic splitting (Krishnan and Fergus 2009), in overlapping FFT tiles.
    /// The GPU keeps each tile for every pass. The CPU path is the result when the GPU is missing or the frame is an odd size.
    static func deconvolve(_ plane: [Float], _ w: Int, _ h: Int, sigma: Float, gpu: Bool = false) -> [Float]? {
        if gpu, let metal = SpotGPU.deconvolve(plane, w, h, sigma: sigma) { return metal }
        let log2n = vDSP_Length(9)
        let n = 1 << 9
        let margin = 96
        let core = n - 2 * margin
        let count = n * n
        let lambda: Float = 0.3
        let betaStart: Float = 0.03
        let passes = 8

        func fft(_ re: inout [Float], _ im: inout [Float], _ dir: Int) {
            let setup = fftSetup(log2n)
            re.withUnsafeMutableBufferPointer { r in
                im.withUnsafeMutableBufferPointer { i in
                    var split = DSPSplitComplex(realp: r.baseAddress!, imagp: i.baseAddress!)
                    vDSP_fft2d_zip(setup, &split, 1, 0, log2n, log2n, FFTDirection(Int32(dir)))
                }
            }
        }

        var hr = [Float](repeating: 0, count: count)
        var hi = [Float](repeating: 0, count: count)
        let rad = Int(ceil(sigma * 4))
        var sum: Float = 0
        for dy in -rad...rad {
            for dx in -rad...rad {
                let v = exp(-0.5 * Float(dx * dx + dy * dy) / (sigma * sigma))
                hr[((dy + n) % n) * n + (dx + n) % n] += v
                sum += v
            }
        }
        for i in 0..<count { hr[i] /= sum }
        fft(&hr, &hi, kFFTDirection_Forward)
        var h2 = [Float](repeating: 0, count: count)
        var dxr = h2, dxi = h2, dyr = h2, dyi = h2, d2 = h2
        for v in 0..<n {
            let wy = 2 * Float.pi * Float(v) / Float(n)
            for u in 0..<n {
                let i = v * n + u
                let wx = 2 * Float.pi * Float(u) / Float(n)
                h2[i] = hr[i] * hr[i] + hi[i] * hi[i]
                dxr[i] = cos(wx) - 1; dxi[i] = sin(wx)
                dyr[i] = cos(wy) - 1; dyi[i] = sin(wy)
                d2[i] = dxr[i] * dxr[i] + dxi[i] * dxi[i] + dyr[i] * dyr[i] + dyi[i] * dyi[i]
            }
        }

        let tilesX = (w + core - 1) / core
        let tilesY = (h + core - 1) / core
        var out = [Float](repeating: 0, count: w * h)
        out.withUnsafeMutableBufferPointer { dest in
            guard let base = dest.baseAddress else { return }
            DispatchQueue.concurrentPerform(iterations: tilesX * tilesY) { index in
                let tx = (index % tilesX) * core - margin
                let ty = (index / tilesX) * core - margin
                var tile = [Float](repeating: 0, count: count)
                var mean: Float = 0
                for y in 0..<n {
                    let sy = min(h - 1, max(0, ty + y))
                    for x in 0..<n {
                        let sx = min(w - 1, max(0, tx + x))
                        let v = plane[sy * w + sx]
                        tile[y * n + x] = v
                        mean += v
                    }
                }
                mean /= Float(count)
                let band = 64
                for y in 0..<n {
                    for x in 0..<n {
                        let e = min(min(x, n - 1 - x), min(y, n - 1 - y))
                        guard e < band else { continue }
                        let wgt = 0.5 - 0.5 * cos(Float(e) / Float(band) * .pi)
                        tile[y * n + x] = mean + (tile[y * n + x] - mean) * wgt
                    }
                }
                var yr = tile
                var yi = [Float](repeating: 0, count: count)
                fft(&yr, &yi, kFFTDirection_Forward)
                var hyr = [Float](repeating: 0, count: count)
                var hyi = hyr
                for i in 0..<count {
                    hyr[i] = hr[i] * yr[i] + hi[i] * yi[i]
                    hyi[i] = hr[i] * yi[i] - hi[i] * yr[i]
                }
                var x = tile
                var zxr = [Float](repeating: 0, count: count)
                var zxi = zxr, zyr = zxr, zyi = zxr, xr = zxr, xi = zxr
                var beta = betaStart
                for _ in 0..<passes {
                    let th = 1 / beta
                    for yy in 0..<n {
                        let row = yy * n
                        let below = ((yy + 1) % n) * n
                        for xx in 0..<n {
                            let i = row + xx
                            let gx = x[row + (xx + 1) % n] - x[i]
                            let gy = x[below + xx] - x[i]
                            let mag = (gx * gx + gy * gy).squareRoot()
                            let s = mag > th ? (mag - th) / mag : 0
                            zxr[i] = gx * s
                            zyr[i] = gy * s
                        }
                    }
                    for i in 0..<count { zxi[i] = 0; zyi[i] = 0 }
                    fft(&zxr, &zxi, kFFTDirection_Forward)
                    fft(&zyr, &zyi, kFFTDirection_Forward)
                    for i in 0..<count {
                        let ar = dxr[i] * zxr[i] + dxi[i] * zxi[i] + dyr[i] * zyr[i] + dyi[i] * zyi[i]
                        let ai = dxr[i] * zxi[i] - dxi[i] * zxr[i] + dyr[i] * zyi[i] - dyi[i] * zyr[i]
                        let den = max(lambda * h2[i] + beta * d2[i], 1e-8)
                        xr[i] = (lambda * hyr[i] + beta * ar) / den
                        xi[i] = (lambda * hyi[i] + beta * ai) / den
                    }
                    fft(&xr, &xi, kFFTDirection_Inverse)
                    let scale = 1 / Float(count)
                    for i in 0..<count { x[i] = xr[i] * scale }
                    beta *= 2
                }
                for y in margin..<(n - margin) {
                    let dy = ty + y
                    guard dy >= 0, dy < h else { continue }
                    for xx in margin..<(n - margin) {
                        let dx = tx + xx
                        guard dx >= 0, dx < w else { continue }
                        base[dy * w + dx] = x[y * n + xx]
                    }
                }
            }
        }
        return out
    }
}
