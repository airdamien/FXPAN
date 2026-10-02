import Accelerate
import CoreGraphics
import Darwin
import Foundation

/// The Pi's Hugin stitch: SIFT in the overlap, a similarity (scale, rotation, shift), then a five-band blend.
/// A miss returns nil and the caller feathers the rig overlap.
enum Hugin {
    struct Made {
        var image: CGImage
        var overlap: Double
        var dy: Int
        var rot: Double
        var scale: Double
        var inliers: Int
        var blend: String
    }

    struct Affine {
        var a: Double
        var b: Double
        var tx: Double
        var ty: Double

        var scale: Double { (a * a + b * b).squareRoot() }
        var rotDeg: Double { atan2(b, a) * 180 / .pi }

        func apply(_ x: Double, _ y: Double) -> (Double, Double) {
            (a * x - b * y + tx, b * x + a * y + ty)
        }

        func invert(_ x: Double, _ y: Double) -> (Double, Double) {
            let s2 = a * a + b * b
            let dx = x - tx
            let dy = y - ty
            return ((a * dx + b * dy) / s2, (-b * dx + a * dy) / s2)
        }
    }

    static func make(t: CGImage, r: CGImage, overlap: Double) -> Made? {
        let tr = rgba(from: t)
        let rr = rgba(from: r)
        guard tr.w == rr.w, tr.h == rr.h, tr.w > 32, tr.h > 32 else { return nil }
        guard let fit = align(t: tr, r: rr, overlap: overlap) else { return nil }
        guard let warped = warp(t: tr, r: rr, fit: fit) else { return nil }
        let cropped = crop(warped)
        let useBands = memoryAllowsBands(w: cropped.w, h: cropped.h)
        let px: [UInt8]
        let blend: String
        if useBands, let blended = multiband(r: cropped.r, t: cropped.t, w: cropped.w, h: cropped.h, bands: 5) {
            px = blended
            blend = "multiband"
        } else if let soft = feather(r: cropped.r, t: cropped.t, w: cropped.w, h: cropped.h) {
            px = soft
            blend = "feather"
        } else {
            return nil
        }
        guard let image = cgImage(rgba: px, w: cropped.w, h: cropped.h) else { return nil }
        let made = Made(
            image: image, overlap: fit.overlap, dy: fit.dy, rot: fit.rot, scale: fit.scale,
            inliers: fit.inliers, blend: blend
        )
        print(String(
            format: "FXPAN hugin rot=%+.2f° scale=%.4f ol=%.0f%% dy=%+d n=%d %@",
            made.rot, made.scale, made.overlap * 100, made.dy, made.inliers, made.blend
        ))
        return made
    }

    // MARK: - Align

    struct Fit {
        var m: Affine
        var overlap: Double
        var dy: Int
        var rot: Double
        var scale: Double
        var inliers: Int
    }

    static func align(t pxT: RGBA, r pxR: RGBA, overlap: Double) -> Fit? {
        let fullW = pxR.w
        let fullH = pxR.h
        let workW = min(fullW, 1600)
        let gT = scale(gray(pxT), width: workW)
        let gR = scale(gray(pxR), width: workW)
        guard gT.w == gR.w, gT.h == gR.h else { return nil }
        let band = min(gR.w / 2, max(Int((Double(gR.w) * overlap * 1.5).rounded()), Int((Double(gR.w) * 0.22).rounded())))
        let kR = describe(detect(gR) { $0 >= gR.w - band }, on: gR)
        let kT = describe(detect(gT) { $0 <= band }, on: gT)
        guard kR.count >= 8, kT.count >= 8 else { return nil }
        guard let matched = match(left: kR, right: kT, height: gR.h), matched.count >= 8 else { return nil }
        guard let mWork = ransac(matched) else { return nil }
        let s = Double(gR.w) / Double(fullW)
        let full = Affine(a: mWork.a, b: mWork.b, tx: mWork.tx / s, ty: mWork.ty / s)
        guard sane(full, w: fullW, h: fullH) else { return nil }
        let frac = (Double(fullW) - full.tx) / Double(fullW)
        return Fit(
            m: full, overlap: frac, dy: Int(full.ty.rounded()),
            rot: full.rotDeg, scale: full.scale, inliers: mWork.inliers
        )
    }

    private static func sane(_ m: Affine, w: Int, h: Int) -> Bool {
        let sc = m.scale
        if sc < 0.94 || sc > 1.06 || sc.isNaN { return false }
        if abs(m.rotDeg) > 8 { return false }
        if m.tx < 0.40 * Double(w) || m.tx > 0.95 * Double(w) { return false }
        if abs(m.ty) > 0.20 * Double(h) { return false }
        let frac = (Double(w) - m.tx) / Double(w)
        return frac >= 0.05 && frac <= 0.50
    }

    // MARK: - SIFT

    private struct KP {
        var x: Float
        var y: Float
        var sigma: Float
        var angle: Float
        var response: Float
        var d: [Float]
    }

    private final class Gray {
        let w: Int
        let h: Int
        var p: [Float]
        init(w: Int, h: Int, p: [Float]) {
            self.w = w
            self.h = h
            self.p = p
        }
        func at(_ x: Int, _ y: Int) -> Float {
            p[min(h - 1, max(0, y)) * w + min(w - 1, max(0, x))]
        }
    }

    private static func detect(_ img: Gray, keepX: (Int) -> Bool) -> [(x: Float, y: Float, sigma: Float, response: Float)] {
        let layers = 3
        let sigma0 = 1.6
        let k = pow(2.0, 1.0 / Double(layers))
        var gauss: [[Gray]] = []
        var current = blur(img, sigma: (sigma0 * sigma0 - 0.25).squareRoot())
        let octaves = max(1, min(5, Int(log2(Double(min(img.w, img.h)))) - 3))
        var blurSteps = [Double](repeating: 0, count: layers + 3)
        for i in 1..<(layers + 3) {
            let prev = pow(k, Double(i - 1)) * sigma0
            let total = prev * k
            blurSteps[i] = (total * total - prev * prev).squareRoot()
        }
        for oct in 0..<octaves {
            var level: [Gray] = [current]
            for i in 1..<(layers + 3) {
                level.append(blur(level[i - 1], sigma: blurSteps[i]))
            }
            gauss.append(level)
            if oct + 1 < octaves {
                let src = level[layers]
                let nw = src.w / 2
                let nh = src.h / 2
                if nw < 16 || nh < 16 { break }
                var p = [Float](repeating: 0, count: nw * nh)
                for y in 0..<nh {
                    for x in 0..<nw { p[y * nw + x] = src.p[(y * 2) * src.w + x * 2] }
                }
                current = Gray(w: nw, h: nh, p: p)
            }
        }
        let prelim = Float(0.5 * 0.02 / Double(layers))
        var found: [(x: Float, y: Float, sigma: Float, response: Float)] = []
        for oct in 0..<gauss.count {
            let g = gauss[oct]
            let dogs = (0..<(g.count - 1)).map { dog(g[$0], g[$0 + 1]) }
            let scale = Float(1 << oct)
            for li in 1..<(dogs.count - 1) {
                let d0 = dogs[li - 1], d1 = dogs[li], d2 = dogs[li + 1]
                let w = d1.w, h = d1.h
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) {
                        let wx = Int(Float(x) * scale)
                        if !keepX(wx) { continue }
                        let c = d1.p[y * w + x]
                        if abs(c) < prelim { continue }
                        if !extreme(c, x, y, d0, d1, d2) { continue }
                        if !edgeOK(d1, x, y) { continue }
                        let sig = Float(sigma0 * pow(k, Double(li)) * Double(scale))
                        found.append((Float(x) * scale, Float(y) * scale, sig, abs(c)))
                    }
                }
            }
        }
        found.sort { $0.response > $1.response }
        if found.count > 800 { found.removeLast(found.count - 800) }
        return found
    }

    private static func dog(_ a: Gray, _ b: Gray) -> Gray {
        var p = [Float](repeating: 0, count: a.p.count)
        for i in 0..<p.count { p[i] = a.p[i] - b.p[i] }
        return Gray(w: a.w, h: a.h, p: p)
    }

    private static func extreme(_ c: Float, _ x: Int, _ y: Int, _ a: Gray, _ b: Gray, _ d: Gray) -> Bool {
        let hi = c > 0
        for yy in (y - 1)...(y + 1) {
            for xx in (x - 1)...(x + 1) {
                for plane in [a, b, d] {
                    if plane === b && xx == x && yy == y { continue }
                    let v = plane.p[yy * plane.w + xx]
                    if hi ? v >= c : v <= c { return false }
                }
            }
        }
        return true
    }

    private static func edgeOK(_ d: Gray, _ x: Int, _ y: Int) -> Bool {
        let w = d.w
        let c = d.p[y * w + x]
        let dxx = d.p[y * w + x + 1] + d.p[y * w + x - 1] - 2 * c
        let dyy = d.p[(y + 1) * w + x] + d.p[(y - 1) * w + x] - 2 * c
        let dxy = (d.p[(y + 1) * w + x + 1] - d.p[(y + 1) * w + x - 1] - d.p[(y - 1) * w + x + 1] + d.p[(y - 1) * w + x - 1]) * 0.25
        let tr = dxx + dyy
        let det = dxx * dyy - dxy * dxy
        if det <= 1e-12 { return false }
        let r: Float = 10
        return tr * tr * r < (r + 1) * (r + 1) * det
    }

    private static func describe(_ seeds: [(x: Float, y: Float, sigma: Float, response: Float)], on img: Gray) -> [KP] {
        var out: [KP] = []
        out.reserveCapacity(seeds.count)
        for s in seeds {
            for angle in orient(img, x: s.x, y: s.y, sigma: s.sigma) {
                guard let d = descriptor(img, x: s.x, y: s.y, sigma: s.sigma, angle: angle) else { continue }
                out.append(KP(x: s.x, y: s.y, sigma: s.sigma, angle: angle, response: s.response, d: d))
            }
        }
        return out
    }

    private static func orient(_ img: Gray, x: Float, y: Float, sigma: Float) -> [Float] {
        let radius = max(2, Int((4.5 * sigma).rounded()))
        var hist = [Float](repeating: 0, count: 36)
        let sig = 1.5 * sigma
        let ix = Int(x.rounded()), iy = Int(y.rounded())
        for yy in (iy - radius)...(iy + radius) {
            if yy < 1 || yy >= img.h - 1 { continue }
            for xx in (ix - radius)...(ix + radius) {
                if xx < 1 || xx >= img.w - 1 { continue }
                let dx = img.at(xx + 1, yy) - img.at(xx - 1, yy)
                let dy = img.at(xx, yy + 1) - img.at(xx, yy - 1)
                let mag = (dx * dx + dy * dy).squareRoot()
                var ang = atan2(dy, dx)
                if ang < 0 { ang += 2 * .pi }
                let dx0 = Float(xx) - x
                let dy0 = Float(yy) - y
                let wgt = exp(-0.5 * (dx0 * dx0 + dy0 * dy0) / (sig * sig))
                let bin = ang * 36 / (2 * .pi)
                let b0 = Int(bin) % 36
                let f = bin - Float(Int(bin))
                hist[b0] += mag * wgt * (1 - f)
                hist[(b0 + 1) % 36] += mag * wgt * f
            }
        }
        for _ in 0..<2 {
            var next = hist
            for i in 0..<36 {
                next[i] = (hist[(i + 35) % 36] + hist[i] + hist[(i + 1) % 36]) / 3
            }
            hist = next
        }
        let peak = hist.max() ?? 0
        if peak < 1e-6 { return [0] }
        var angles: [Float] = []
        for i in 0..<36 where hist[i] >= 0.8 * peak && hist[i] > hist[(i + 35) % 36] && hist[i] > hist[(i + 1) % 36] {
            let y0 = hist[(i + 35) % 36]
            let y1 = hist[i]
            let y2 = hist[(i + 1) % 36]
            let denom = y0 - 2 * y1 + y2
            let off: Float = abs(denom) < 1e-8 ? 0 : 0.5 * (y0 - y2) / denom
            var ang = (Float(i) + off) * 2 * .pi / 36
            if ang < 0 { ang += 2 * .pi }
            if ang >= 2 * .pi { ang -= 2 * .pi }
            angles.append(ang)
        }
        return angles.isEmpty ? [0] : angles
    }

    private static func descriptor(_ img: Gray, x: Float, y: Float, sigma: Float, angle: Float) -> [Float]? {
        let histWidth = 3 * sigma
        if histWidth < 1 { return nil }
        let radius = Int((histWidth * 2.5 * 1.41421356).rounded())
        let cosT = cos(-angle)
        let sinT = sin(-angle)
        var hist = [Float](repeating: 0, count: 128)
        let ix = Int(x.rounded()), iy = Int(y.rounded())
        let winSig = 2 * histWidth
        for yy in (iy - radius)...(iy + radius) {
            if yy < 1 || yy >= img.h - 1 { continue }
            for xx in (ix - radius)...(ix + radius) {
                if xx < 1 || xx >= img.w - 1 { continue }
                let dx0 = Float(xx) - x
                let dy0 = Float(yy) - y
                let rx = cosT * dx0 - sinT * dy0
                let ry = sinT * dx0 + cosT * dy0
                let col = rx / histWidth + 1.5
                let row = ry / histWidth + 1.5
                if col < -0.5 || col >= 3.5 || row < -0.5 || row >= 3.5 { continue }
                let gx = img.at(xx + 1, yy) - img.at(xx - 1, yy)
                let gy = img.at(xx, yy + 1) - img.at(xx, yy - 1)
                let mag = (gx * gx + gy * gy).squareRoot()
                var ang = atan2(gy, gx) - angle
                if ang < 0 { ang += 2 * .pi }
                if ang >= 2 * .pi { ang -= 2 * .pi }
                let ob = ang * 8 / (2 * .pi)
                let wgt = exp(-0.5 * (rx * rx + ry * ry) / (winSig * winSig))
                splat(&hist, row: row, col: col, ob: ob, value: mag * wgt)
            }
        }
        var norm = hist.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm < 1e-6 { return nil }
        for i in 0..<128 { hist[i] /= norm }
        for i in 0..<128 where hist[i] > 0.2 { hist[i] = 0.2 }
        norm = hist.reduce(0) { $0 + $1 * $1 }.squareRoot()
        if norm < 1e-6 { return nil }
        for i in 0..<128 { hist[i] /= norm }
        return hist
    }

    private static func splat(_ hist: inout [Float], row: Float, col: Float, ob: Float, value: Float) {
        let r0 = Int(floor(row))
        let c0 = Int(floor(col))
        let o0 = Int(floor(ob)) % 8
        let rf = row - Float(r0)
        let cf = col - Float(c0)
        let of = ob - floor(ob)
        for dr in 0...1 {
            let rr = r0 + dr
            if rr < 0 || rr > 3 { continue }
            let rw = dr == 0 ? (1 - rf) : rf
            for dc in 0...1 {
                let cc = c0 + dc
                if cc < 0 || cc > 3 { continue }
                let cw = dc == 0 ? (1 - cf) : cf
                for ddo in 0...1 {
                    let oo = (o0 + ddo) & 7
                    let ow = ddo == 0 ? (1 - of) : of
                    hist[(rr * 4 + cc) * 8 + oo] += value * rw * cw * ow
                }
            }
        }
    }

    private static func match(left: [KP], right: [KP], height: Int) -> [(l: KP, r: KP)]? {
        let gate = Float(height) * 0.35
        var pairs: [(l: KP, r: KP)] = []
        for q in right {
            var best = Float.greatestFiniteMagnitude
            var second = Float.greatestFiniteMagnitude
            var who: KP?
            for c in left {
                if abs(c.y - q.y) > gate { continue }
                var s: Float = 0
                for i in 0..<128 {
                    let d = q.d[i] - c.d[i]
                    s += d * d
                    if s >= second { break }
                }
                if s < best {
                    second = best
                    best = s
                    who = c
                } else if s < second {
                    second = s
                }
            }
            if let who, best < 0.64 * second {
                pairs.append((who, q))
            }
        }
        return pairs
    }

    private struct Solved {
        var a: Double
        var b: Double
        var tx: Double
        var ty: Double
        var inliers: Int
    }

    private static func ransac(_ pairs: [(l: KP, r: KP)]) -> Solved? {
        var rng = UInt64(0x9E3779B97F4A7C15)
        func next(_ n: Int) -> Int {
            rng = rng &* 6364136223846793005 &+ 1
            return Int(rng % UInt64(n))
        }
        let n = pairs.count
        var bestInliers: [Int] = []
        let thresh = 4.0 * 4.0
        for _ in 0..<400 {
            let i = next(n)
            let j = next(n)
            if i == j { continue }
            let a = pairs[i], b = pairs[j]
            let vx = Double(b.r.x - a.r.x)
            let vy = Double(b.r.y - a.r.y)
            let den = vx * vx + vy * vy
            if den < 64 { continue }
            let du = Double(b.l.x - a.l.x)
            let dv = Double(b.l.y - a.l.y)
            let aa = (vx * du + vy * dv) / den
            let bb = (vx * dv - vy * du) / den
            let tx = Double(a.l.x) - aa * Double(a.r.x) + bb * Double(a.r.y)
            let ty = Double(a.l.y) - bb * Double(a.r.x) - aa * Double(a.r.y)
            var inl: [Int] = []
            inl.reserveCapacity(n)
            for k in 0..<n {
                let p = pairs[k]
                let x = aa * Double(p.r.x) - bb * Double(p.r.y) + tx
                let y = bb * Double(p.r.x) + aa * Double(p.r.y) + ty
                let ex = x - Double(p.l.x)
                let ey = y - Double(p.l.y)
                if ex * ex + ey * ey <= thresh { inl.append(k) }
            }
            if inl.count > bestInliers.count { bestInliers = inl }
        }
        guard bestInliers.count >= 6 else { return nil }
        return refit(pairs, bestInliers)
    }

    private static func refit(_ pairs: [(l: KP, r: KP)], _ idx: [Int]) -> Solved? {
        var mx = 0.0, my = 0.0, mu = 0.0, mv = 0.0
        for i in idx {
            mx += Double(pairs[i].r.x)
            my += Double(pairs[i].r.y)
            mu += Double(pairs[i].l.x)
            mv += Double(pairs[i].l.y)
        }
        let n = Double(idx.count)
        mx /= n; my /= n; mu /= n; mv /= n
        var dot = 0.0, cross = 0.0, src = 0.0
        for i in idx {
            let sx = Double(pairs[i].r.x) - mx
            let sy = Double(pairs[i].r.y) - my
            let dx = Double(pairs[i].l.x) - mu
            let dy = Double(pairs[i].l.y) - mv
            dot += sx * dx + sy * dy
            cross += sx * dy - sy * dx
            src += sx * sx + sy * sy
        }
        if src < 1 { return nil }
        let a = dot / src
        let b = cross / src
        let tx = mu - a * mx + b * my
        let ty = mv - b * mx - a * my
        return Solved(a: a, b: b, tx: tx, ty: ty, inliers: idx.count)
    }

    private static func blur(_ src: Gray, sigma: Double) -> Gray {
        if sigma < 0.05 { return src }
        let radius = max(1, Int((3 * sigma).rounded()))
        var kernel = [Float](repeating: 0, count: radius * 2 + 1)
        var sum = 0.0
        for i in -radius...radius {
            let v = exp(-0.5 * Double(i * i) / (sigma * sigma))
            kernel[i + radius] = Float(v)
            sum += v
        }
        for i in 0..<kernel.count { kernel[i] /= Float(sum) }
        var mid = [Float](repeating: 0, count: src.p.count)
        let w = src.w, h = src.h
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in -radius...radius {
                    let xx = min(w - 1, max(0, x + k))
                    acc += src.p[y * w + xx] * kernel[k + radius]
                }
                mid[y * w + x] = acc
            }
        }
        var out = [Float](repeating: 0, count: src.p.count)
        for y in 0..<h {
            for x in 0..<w {
                var acc: Float = 0
                for k in -radius...radius {
                    let yy = min(h - 1, max(0, y + k))
                    acc += mid[yy * w + x] * kernel[k + radius]
                }
                out[y * w + x] = acc
            }
        }
        return Gray(w: w, h: h, p: out)
    }

    // MARK: - Warp and blend

    private struct Canvas {
        var r: [UInt8]
        var t: [UInt8]
        var w: Int
        var h: Int
    }

    private static func warp(t: RGBA, r: RGBA, fit: Fit) -> Canvas? {
        let w = t.w, h = t.h
        let corners = [(0.0, 0.0), (Double(w), 0), (Double(w), Double(h)), (0, Double(h))]
        var xs: [Double] = []
        var ys: [Double] = []
        for c in corners {
            xs.append(c.0); ys.append(c.1)
            let p = fit.m.apply(c.0, c.1)
            xs.append(p.0); ys.append(p.1)
        }
        guard let minX = xs.min(), let minY = ys.min(), let maxX = xs.max(), let maxY = ys.max() else { return nil }
        let x0 = floor(minX), y0 = floor(minY)
        let cw = Int(ceil(maxX) - x0)
        let ch = Int(ceil(maxY) - y0)
        if cw < 16 || ch < 16 || cw > w * 3 || ch > h * 2 { return nil }
        let pixels = cw * ch
        if pixels > 80_000_000 { return nil }
        var rpx = [UInt8](repeating: 0, count: pixels * 4)
        var tpx = [UInt8](repeating: 0, count: pixels * 4)
        let mt = Affine(a: fit.m.a, b: fit.m.b, tx: fit.m.tx - x0, ty: fit.m.ty - y0)
        for y in 0..<ch {
            for x in 0..<cw {
                let rx = Double(x) + x0
                let ry = Double(y) + y0
                if let s = sample(r, rx, ry) {
                    let i = (y * cw + x) * 4
                    rpx[i] = s.0; rpx[i + 1] = s.1; rpx[i + 2] = s.2; rpx[i + 3] = 255
                }
                let src = mt.invert(Double(x), Double(y))
                if let s = sample(t, src.0, src.1) {
                    let i = (y * cw + x) * 4
                    tpx[i] = s.0; tpx[i + 1] = s.1; tpx[i + 2] = s.2; tpx[i + 3] = 255
                }
            }
        }
        return Canvas(r: rpx, t: tpx, w: cw, h: ch)
    }

    private static func sample(_ img: RGBA, _ x: Double, _ y: Double) -> (UInt8, UInt8, UInt8)? {
        if x < 0 || y < 0 || x >= Double(img.w - 1) || y >= Double(img.h - 1) { return nil }
        let x0 = Int(x), y0 = Int(y)
        let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
        let i00 = (y0 * img.w + x0) * 4
        let i10 = i00 + 4
        let i01 = i00 + img.w * 4
        let i11 = i01 + 4
        var out = (UInt8(0), UInt8(0), UInt8(0))
        var rgb = [UInt8](repeating: 0, count: 3)
        for c in 0..<3 {
            let v = (1 - fx) * (1 - fy) * Float(img.px[i00 + c])
                + fx * (1 - fy) * Float(img.px[i10 + c])
                + (1 - fx) * fy * Float(img.px[i01 + c])
                + fx * fy * Float(img.px[i11 + c])
            rgb[c] = UInt8(min(255, max(0, v.rounded())))
        }
        out = (rgb[0], rgb[1], rgb[2])
        return out
    }

    private static func crop(_ canvas: Canvas) -> Canvas {
        let w = canvas.w, h = canvas.h
        var opaque = [Bool](repeating: false, count: w)
        var top = [Int](repeating: 0, count: w)
        var bot = [Int](repeating: 0, count: w)
        for x in 0..<w {
            var first = -1
            var last = -1
            for y in 0..<h {
                let i = (y * w + x) * 4
                if canvas.r[i + 3] > 32 || canvas.t[i + 3] > 32 {
                    if first < 0 { first = y }
                    last = y
                }
            }
            if first >= 0 {
                opaque[x] = true
                top[x] = first
                bot[x] = last
            }
        }
        let cols = opaque.enumerated().filter { $0.element }.map { $0.offset }
        guard let x0 = cols.first, let x1 = cols.last, x1 > x0 else { return canvas }
        var heights: [Int] = []
        for x in cols { heights.append(bot[x] - top[x] + 1) }
        heights.sort()
        let med = heights[heights.count / 2]
        var y0 = 0
        var y1 = h
        var tops: [Int] = []
        var bots: [Int] = []
        for x in cols where bot[x] - top[x] + 1 >= Int(Double(med) * 0.90) {
            tops.append(top[x])
            bots.append(bot[x])
        }
        if let tMax = tops.max(), let bMin = bots.min(), bMin > tMax + 8 {
            y0 = tMax
            y1 = bMin + 1
        }
        let cw = x1 - x0 + 1
        let ch = y1 - y0
        if cw < 16 || ch < 16 { return canvas }
        var r = [UInt8](repeating: 0, count: cw * ch * 4)
        var t = [UInt8](repeating: 0, count: cw * ch * 4)
        for y in 0..<ch {
            let s = ((y0 + y) * w + x0) * 4
            let d = y * cw * 4
            r.replaceSubrange(d..<(d + cw * 4), with: canvas.r[s..<(s + cw * 4)])
            t.replaceSubrange(d..<(d + cw * 4), with: canvas.t[s..<(s + cw * 4)])
        }
        return Canvas(r: r, t: t, w: cw, h: ch)
    }

    private static func memoryAllowsBands(w: Int, h: Int) -> Bool {
        #if os(iOS)
        let avail = os_proc_available_memory()
        if avail == 0 { return true }
        let need = UInt64(w) * UInt64(h) * 36
        return avail > need
        #else
        _ = (w, h)
        return true
        #endif
    }

    private static func multiband(r: [UInt8], t: [UInt8], w: Int, h: Int, bands: Int) -> [UInt8]? {
        let weight = seam(r, t, w, h)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for c in 0..<3 {
            let rc = plane(r, w, h, c)
            let tc = plane(t, w, h, c)
            let blended = blendPlanes(rc, tc, weight, w, h, bands: bands)
            for i in 0..<w * h {
                out[i * 4 + c] = UInt8(min(255, max(0, blended[i].rounded())))
            }
        }
        for i in 0..<w * h {
            let a = r[i * 4 + 3] > 32 || t[i * 4 + 3] > 32
            out[i * 4 + 3] = a ? 255 : 0
        }
        return out
    }

    private static func blendPlanes(_ r: [Float], _ t: [Float], _ wgt: [Float], _ w: Int, _ h: Int, bands: Int) -> [Float] {
        var gr: [[Float]] = [r]
        var gt: [[Float]] = [t]
        var gw: [[Float]] = [wgt]
        var sizes: [(Int, Int)] = [(w, h)]
        var cw = w, ch = h
        for _ in 1..<bands {
            let (nr, nw, nh) = pyrDown(gr.last!, cw, ch)
            if nw < 8 || nh < 8 { break }
            gr.append(nr)
            gt.append(pyrDown(gt.last!, cw, ch).0)
            gw.append(pyrDown(gw.last!, cw, ch).0)
            sizes.append((nw, nh))
            cw = nw
            ch = nh
        }
        let last = gr.count - 1
        var acc = [Float](repeating: 0, count: gr[last].count)
        mix(&acc, gr[last], gt[last], gw[last])
        if last == 0 { return acc }
        for level in stride(from: last - 1, through: 0, by: -1) {
            let upAcc = pyrUp(acc, sizes[level + 1].0, sizes[level + 1].1, sizes[level].0, sizes[level].1)
            let upR = pyrUp(gr[level + 1], sizes[level + 1].0, sizes[level + 1].1, sizes[level].0, sizes[level].1)
            let upT = pyrUp(gt[level + 1], sizes[level + 1].0, sizes[level + 1].1, sizes[level].0, sizes[level].1)
            var lapR = gr[level]
            var lapT = gt[level]
            for i in 0..<lapR.count {
                lapR[i] -= upR[i]
                lapT[i] -= upT[i]
            }
            var lap = [Float](repeating: 0, count: lapR.count)
            mix(&lap, lapR, lapT, gw[level])
            acc = upAcc
            for i in 0..<acc.count { acc[i] += lap[i] }
        }
        return acc
    }

    private static func mix(_ dst: inout [Float], _ r: [Float], _ t: [Float], _ w: [Float]) {
        for i in 0..<dst.count {
            let a = min(1, max(0, w[i]))
            dst[i] = r[i] * a + t[i] * (1 - a)
        }
    }

    private static func feather(r: [UInt8], t: [UInt8], w: Int, h: Int) -> [UInt8]? {
        var weight = seam(r, t, w, h)
        let radius = min(96, max(16, w / 80))
        weight = box(weight, w, h, radius: radius)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<w * h {
            let ra = r[i * 4 + 3] > 32
            let ta = t[i * 4 + 3] > 32
            let a = min(1, max(0, weight[i]))
            for c in 0..<3 {
                let rv = Float(r[i * 4 + c])
                let tv = Float(t[i * 4 + c])
                let v: Float
                if ra && ta { v = rv * a + tv * (1 - a) }
                else if ra { v = rv }
                else { v = tv }
                out[i * 4 + c] = UInt8(min(255, max(0, v.rounded())))
            }
            out[i * 4 + 3] = (ra || ta) ? 255 : 0
        }
        return out
    }

    private static func seam(_ r: [UInt8], _ t: [UInt8], _ w: Int, _ h: Int) -> [Float] {
        let n = w * h
        var distR = [Int](repeating: 1_000_000, count: n)
        var distT = [Int](repeating: 1_000_000, count: n)
        for i in 0..<n {
            let rr = r[i * 4 + 3] > 32
            let tt = t[i * 4 + 3] > 32
            if rr && !tt { distR[i] = 0 }
            if tt && !rr { distT[i] = 0 }
        }
        chamfer(&distR, w, h)
        chamfer(&distT, w, h)
        var weight = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let rr = r[i * 4 + 3] > 32
            let tt = t[i * 4 + 3] > 32
            if rr && !tt { weight[i] = 1 }
            else if rr && tt { weight[i] = distR[i] <= distT[i] ? 1 : 0 }
        }
        return weight
    }

    private static func chamfer(_ d: inout [Int], _ w: Int, _ h: Int) {
        for _ in 0..<2 {
            for y in 0..<h {
                for x in 0..<w {
                    var v = d[y * w + x]
                    if x > 0 { v = min(v, d[y * w + x - 1] + 1) }
                    if y > 0 { v = min(v, d[(y - 1) * w + x] + 1) }
                    d[y * w + x] = v
                }
            }
            for y in stride(from: h - 1, through: 0, by: -1) {
                for x in stride(from: w - 1, through: 0, by: -1) {
                    var v = d[y * w + x]
                    if x + 1 < w { v = min(v, d[y * w + x + 1] + 1) }
                    if y + 1 < h { v = min(v, d[(y + 1) * w + x] + 1) }
                    d[y * w + x] = v
                }
            }
        }
    }

    private static func plane(_ px: [UInt8], _ w: Int, _ h: Int, _ c: Int) -> [Float] {
        var o = [Float](repeating: 0, count: w * h)
        for i in 0..<w * h { o[i] = Float(px[i * 4 + c]) }
        return o
    }

    private static func pyrDown(_ src: [Float], _ w: Int, _ h: Int) -> ([Float], Int, Int) {
        let blurred = blur5(src, w, h)
        let nw = max(1, w / 2)
        let nh = max(1, h / 2)
        var dst = [Float](repeating: 0, count: nw * nh)
        for y in 0..<nh {
            let sy = min(h - 1, y * 2)
            for x in 0..<nw {
                let sx = min(w - 1, x * 2)
                dst[y * nw + x] = blurred[sy * w + sx]
            }
        }
        return (dst, nw, nh)
    }

    private static func pyrUp(_ src: [Float], _ w: Int, _ h: Int, _ tw: Int, _ th: Int) -> [Float] {
        var tmp = [Float](repeating: 0, count: tw * th)
        for y in 0..<h {
            let dy = y * 2
            if dy >= th { break }
            for x in 0..<w {
                let dx = x * 2
                if dx >= tw { break }
                tmp[dy * tw + dx] = src[y * w + x]
            }
        }
        return blur5(tmp, tw, th).map { $0 * 4 }
    }

    private static func blur5(_ src: [Float], _ w: Int, _ h: Int) -> [Float] {
        let k1: [Float] = [1, 4, 6, 4, 1].map { $0 / 16 }
        var kernel = [Float](repeating: 0, count: 25)
        for y in 0..<5 {
            for x in 0..<5 { kernel[y * 5 + x] = k1[y] * k1[x] }
        }
        var srcCopy = src
        var dst = [Float](repeating: 0, count: w * h)
        srcCopy.withUnsafeMutableBufferPointer { sbuf in
            dst.withUnsafeMutableBufferPointer { dbuf in
                var srcB = vImage_Buffer(data: sbuf.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * MemoryLayout<Float>.stride)
                var dstB = vImage_Buffer(data: dbuf.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: w * MemoryLayout<Float>.stride)
                _ = vImageConvolve_PlanarF(&srcB, &dstB, nil, 0, 0, &kernel, 5, 5, 0, vImage_Flags(kvImageEdgeExtend))
            }
        }
        return dst
    }

    private static func box(_ src: [Float], _ w: Int, _ h: Int, radius: Int) -> [Float] {
        let r = max(1, radius)
        var mid = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            var sum = 0.0
            var prefix = [Double](repeating: 0, count: w + 1)
            for x in 0..<w { prefix[x + 1] = prefix[x] + Double(src[y * w + x]) }
            for x in 0..<w {
                let a = max(0, x - r)
                let b = min(w - 1, x + r)
                sum = (prefix[b + 1] - prefix[a]) / Double(b - a + 1)
                mid[y * w + x] = Float(sum)
            }
        }
        var dst = [Float](repeating: 0, count: w * h)
        for x in 0..<w {
            var prefix = [Double](repeating: 0, count: h + 1)
            for y in 0..<h { prefix[y + 1] = prefix[y] + Double(mid[y * w + x]) }
            for y in 0..<h {
                let a = max(0, y - r)
                let b = min(h - 1, y + r)
                dst[y * w + x] = Float((prefix[b + 1] - prefix[a]) / Double(b - a + 1))
            }
        }
        return dst
    }

    // MARK: - Pixels

    struct RGBA {
        var w: Int
        var h: Int
        var px: [UInt8]
    }

    static func rgba(from image: CGImage) -> RGBA {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cs = CGColorSpaceCreateDeviceRGB()
        px.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return }
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return RGBA(w: w, h: h, px: px)
    }

    static func cgImage(rgba px: [UInt8], w: Int, h: Int) -> CGImage? {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return nil }
        let dst = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let row = w * 4
        px.withUnsafeBytes { src in
            guard let base = src.baseAddress else { return }
            for y in 0..<h {
                memcpy(dst + (h - 1 - y) * row, base + y * row, row)
            }
        }
        return ctx.makeImage()
    }

    private static func gray(_ img: RGBA) -> Gray {
        var p = [Float](repeating: 0, count: img.w * img.h)
        for i in 0..<p.count {
            let o = i * 4
            p[i] = (0.299 * Float(img.px[o]) + 0.587 * Float(img.px[o + 1]) + 0.114 * Float(img.px[o + 2])) / 255
        }
        return Gray(w: img.w, h: img.h, p: p)
    }

    private static func scale(_ src: Gray, width: Int) -> Gray {
        if src.w <= width { return src }
        let h = max(1, Int((Double(src.h) * Double(width) / Double(src.w)).rounded()))
        var p = [Float](repeating: 0, count: width * h)
        for y in 0..<h {
            let sy = min(src.h - 1, Int(Double(y) * Double(src.h) / Double(h)))
            for x in 0..<width {
                let sx = min(src.w - 1, Int(Double(x) * Double(src.w) / Double(width)))
                p[y * width + x] = src.p[sy * src.w + sx]
            }
        }
        return Gray(w: width, h: h, p: p)
    }
}
