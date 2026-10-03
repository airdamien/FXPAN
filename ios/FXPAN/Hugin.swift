import Accelerate
import CoreGraphics
import Foundation

/// The Pi's Hugin stitch: SIFT in the overlap, a similarity (scale, rotation, shift), then a multiband blend.
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
        var frameWidth: Int
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

    static func prepare(t: CGImage, r: CGImage, overlap: Double, frameWidth: Int, balance: Bool = false, metal: Bool = true, note: StitchNote? = nil, stop: StitchStop? = nil) throws -> Prepared? {
        try StitchGate.check(stop)
        note?("Reading the frames")
        let tr = rgba(from: t)
        let rr = rgba(from: r)
        guard tr.w == rr.w, tr.h == rr.h, tr.w > 32, tr.h > 32 else { return nil }
        guard let fit = try align(t: tr, r: rr, overlap: overlap, note: note, stop: stop) else { return nil }
        try StitchGate.check(stop)
        note?(metal ? "Warping on the GPU" : "Warping the frames")
        guard let warped = try warp(t: tr, r: rr, fit: fit, metal: metal, note: note, stop: stop) else { return nil }
        let cropped = crop(warped)
        var pr = cropped.r
        var pt = cropped.t
        if balance {
            note?("Balancing the overlap")
            balancePair(&pr, &pt, cropped.w, cropped.h)
        }
        return Prepared(r: pr, t: pt, w: cropped.w, h: cropped.h, fit: fit, frameWidth: frameWidth)
    }

    /// The source frames and the uncropped warp are already gone. Blend, drop the pair, then pack.
    static func render(_ prepared: Prepared, note: StitchNote? = nil, stop: StitchStop? = nil) throws -> Made {
        var prepared = prepared
        let blended = try blend(&prepared, note: note, stop: stop)
        prepared.r = []
        prepared.t = []
        try StitchGate.check(stop)
        note?("Packing the panorama")
        guard let image = cgImage(rgba: blended.px, w: blended.w, h: blended.h) else {
            throw PTPError.message("Could not pack the panorama")
        }
        let made = Made(
            image: image, overlap: prepared.fit.overlap, dy: prepared.fit.dy, rot: prepared.fit.rot,
            scale: prepared.fit.scale, inliers: prepared.fit.inliers, blend: blended.blend, frameWidth: prepared.frameWidth
        )
        print(String(
            format: "FXPAN hugin rot=%+.2f° scale=%.4f ol=%.0f%% dy=%+d n=%d %@",
            made.rot, made.scale, made.overlap * 100, made.dy, made.inliers, made.blend
        ))
        return made
    }

    struct Prepared {
        var r: [UInt8]
        var t: [UInt8]
        var w: Int
        var h: Int
        var fit: Fit
        var frameWidth: Int
    }

    /// Blend, then drop both warped frames before the caller packs a third copy.
    private static func blend(_ cropped: inout Prepared, note: StitchNote?, stop: StitchStop?) throws -> (px: [UInt8], w: Int, h: Int, blend: String) {
        let useBands = memoryAllowsBands(w: cropped.w, h: cropped.h)
        if useBands {
            let bands = bandCount(overlapPx: Int((cropped.fit.overlap * Double(cropped.frameWidth)).rounded()))
            note?("Blending \(bands) bands")
            if let blended = try multiband(r: cropped.r, t: cropped.t, w: cropped.w, h: cropped.h, bands: bands, stop: stop) {
                return (blended, cropped.w, cropped.h, "multiband")
            }
            try StitchGate.check(stop)
            note?("Feathering the seam")
            guard let soft = feather(r: cropped.r, t: cropped.t, w: cropped.w, h: cropped.h) else {
                throw PTPError.message("Could not feather the seam")
            }
            return (soft, cropped.w, cropped.h, "feather")
        }
        note?("Not enough memory for bands, feathering")
        guard let soft = feather(r: cropped.r, t: cropped.t, w: cropped.w, h: cropped.h) else {
            throw PTPError.message("Could not feather the seam")
        }
        return (soft, cropped.w, cropped.h, "feather")
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

    static func align(t pxT: RGBA, r pxR: RGBA, overlap: Double, note: StitchNote? = nil, stop: StitchStop? = nil) throws -> Fit? {
        let fullW = pxR.w
        let fullH = pxR.h
        let workW = min(fullW, 1600)
        let gT = scale(gray(pxT), width: workW)
        let gR = scale(gray(pxR), width: workW)
        guard gT.w == gR.w, gT.h == gR.h else { return nil }
        let band = min(gR.w / 2, max(Int((Double(gR.w) * overlap * 1.5).rounded()), Int((Double(gR.w) * 0.22).rounded())))
        let pad = 24
        try StitchGate.check(stop)
        note?("Finding features in the R overlap")
        let kR = try features(gR, x0: max(0, gR.w - band - pad), width: band + pad, stop: stop).filter { $0.x >= Float(gR.w - band) }
        try StitchGate.check(stop)
        note?("Finding features in the T overlap")
        let kT = try features(gT, x0: 0, width: min(gT.w, band + pad), stop: stop).filter { $0.x <= Float(band) }
        guard kR.count >= 8, kT.count >= 8 else { return nil }
        try StitchGate.check(stop)
        note?("Matching the overlap")
        guard let matched = match(left: kR, right: kT, height: gR.h), matched.count >= 8 else { return nil }
        try StitchGate.check(stop)
        note?("Fitting the seam")
        guard var mWork = ransac(matched) else { return nil }
        mWork = nudge(mWork, r: gR, t: gT)
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

    /// R is already flopped, so its overlap with T is the right-hand strip. Search only that strip, not the whole frame.
    private static func features(_ img: Gray, x0: Int, width: Int, stop: StitchStop?) throws -> [KP] {
        try StitchGate.check(stop)
        let x0 = max(0, min(img.w - 1, x0))
        let w = max(8, min(img.w - x0, width))
        let strip = cropX(img, from: x0, width: w)
        var keys = try describe(try detect(strip, stop: stop) { _ in true }, on: strip, stop: stop)
        if x0 != 0 {
            for i in keys.indices { keys[i].x += Float(x0) }
        }
        return keys
    }

    private static func cropX(_ src: Gray, from x0: Int, width: Int) -> Gray {
        var p = [Float](repeating: 0, count: width * src.h)
        for y in 0..<src.h {
            let row = y * src.w + x0
            p.replaceSubrange((y * width)..<((y + 1) * width), with: src.p[row..<(row + width)])
        }
        return Gray(w: width, h: src.h, p: p)
    }

    private static func detect(_ img: Gray, stop: StitchStop?, keepX: (Int) -> Bool) throws -> [(x: Float, y: Float, sigma: Float, response: Float)] {
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
            try StitchGate.check(stop)
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

    private static func describe(_ seeds: [(x: Float, y: Float, sigma: Float, response: Float)], on img: Gray, stop: StitchStop?) throws -> [KP] {
        var out: [KP] = []
        out.reserveCapacity(seeds.count)
        for (n, s) in seeds.enumerated() {
            if n % 32 == 0 { try StitchGate.check(stop) }
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

    /// The feature fit splits the difference between near and far. Slide it so the middle of the overlap agrees.
    private static func nudge(_ m: Solved, r: Gray, t: Gray) -> Solved {
        let y0 = Int(Double(r.h) * 0.35)
        let y1 = Int(Double(r.h) * 0.65)
        let x0 = max(8, Int(m.tx) + 8)
        let x1 = r.w - 8
        guard x1 - x0 > 16, y1 - y0 > 16 else { return m }
        var xs: [Int] = []
        var ys: [Int] = []
        var rv: [Float] = []
        for y in stride(from: y0, to: y1, by: 4) {
            for x in stride(from: x0, to: x1, by: 4) {
                xs.append(x)
                ys.append(y)
                rv.append(r.at(x, y))
            }
        }
        guard xs.count > 200 else { return m }
        func score(_ dx: Double, _ dy: Double) -> Double {
            let tx = m.tx + dx
            let ty = m.ty + dy
            let s2 = m.a * m.a + m.b * m.b
            if s2 < 1e-6 { return -1 }
            var num = 0.0, sr = 0.0, st = 0.0, dr = 0.0, dt = 0.0, n = 0.0
            for i in 0..<xs.count {
                let dxv = Double(xs[i]) - tx
                let dyv = Double(ys[i]) - ty
                let u = (m.a * dxv + m.b * dyv) / s2
                let v = (-m.b * dxv + m.a * dyv) / s2
                let ui = Int(u.rounded(.down))
                let vi = Int(v.rounded(.down))
                if ui < 1 || vi < 1 || ui + 1 >= t.w || vi + 1 >= t.h { continue }
                let fu = u - Double(ui)
                let fv = v - Double(vi)
                let tv = Double(t.at(ui, vi)) * (1 - fu) * (1 - fv)
                    + Double(t.at(ui + 1, vi)) * fu * (1 - fv)
                    + Double(t.at(ui, vi + 1)) * (1 - fu) * fv
                    + Double(t.at(ui + 1, vi + 1)) * fu * fv
                let rr = Double(rv[i])
                sr += rr
                st += tv
                dr += rr * rr
                dt += tv * tv
                num += rr * tv
                n += 1
            }
            if n < 150 { return -1 }
            let vr = dr - sr * sr / n
            let vt = dt - st * st / n
            if vr < 1 || vt < 1 { return -1 }
            return (num - sr * st / n) / (vr * vt).squareRoot()
        }
        let base = score(0, 0)
        var best = base
        var bestDx = 0
        var bestDy = 0
        for dy in -16...16 {
            for dx in -16...16 {
                let s = score(Double(dx), Double(dy))
                if s > best {
                    best = s
                    bestDx = dx
                    bestDy = dy
                }
            }
        }
        if abs(bestDx) == 16 || abs(bestDy) == 16 || best < base + 0.004 { return m }
        print(String(format: "FXPAN nudge %+d %+d px at fit size, ncc %.3f -> %.3f", bestDx, bestDy, base, best))
        var out = m
        out.tx += Double(bestDx)
        out.ty += Double(bestDy)
        return out
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
        let w = src.w, h = src.h
        var mid = [Float](repeating: 0, count: src.p.count)
        var out = [Float](repeating: 0, count: src.p.count)
        src.p.withUnsafeBufferPointer { srcBuf in
            mid.withUnsafeMutableBufferPointer { midBuf in
                out.withUnsafeMutableBufferPointer { outBuf in
                    var srcB = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: srcBuf.baseAddress),
                        height: vImagePixelCount(h), width: vImagePixelCount(w),
                        rowBytes: w * MemoryLayout<Float>.stride
                    )
                    var midB = vImage_Buffer(
                        data: midBuf.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w),
                        rowBytes: w * MemoryLayout<Float>.stride
                    )
                    var outB = vImage_Buffer(
                        data: outBuf.baseAddress, height: vImagePixelCount(h), width: vImagePixelCount(w),
                        rowBytes: w * MemoryLayout<Float>.stride
                    )
                    kernel.withUnsafeBufferPointer { kbuf in
                        _ = vImageConvolve_PlanarF(&srcB, &midB, nil, 0, 0, kbuf.baseAddress!, 1, UInt32(kernel.count), 0, vImage_Flags(kvImageEdgeExtend))
                        _ = vImageConvolve_PlanarF(&midB, &outB, nil, 0, 0, kbuf.baseAddress!, UInt32(kernel.count), 1, 0, vImage_Flags(kvImageEdgeExtend))
                    }
                }
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

    private static func warp(t: RGBA, r: RGBA, fit: Fit, metal: Bool, note: StitchNote?, stop: StitchStop?) throws -> Canvas? {
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
        let mt = Affine(a: fit.m.a, b: fit.m.b, tx: fit.m.tx - x0, ty: fit.m.ty - y0)
        if metal, let gpu = WarpGPU.frames(r: r, t: t, x0: x0, y0: y0, cw: cw, ch: ch, mt: mt) {
            return Canvas(r: gpu.r, t: gpu.t, w: cw, h: ch)
        }
        if metal { note?("Warping on the CPU") }
        let started = CFAbsoluteTimeGetCurrent()
        var rpx = [UInt8](repeating: 0, count: pixels * 4)
        var tpx = [UInt8](repeating: 0, count: pixels * 4)
        for y in 0..<ch {
            if y % 32 == 0 { try StitchGate.check(stop) }
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
        print(String(format: "FXPAN warp cpu %dx%d %.2fs", cw, ch, CFAbsoluteTimeGetCurrent() - started))
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
        let p = img.px
        func chan(_ c: Int) -> UInt8 {
            let v = (1 - fx) * (1 - fy) * Float(p[i00 + c])
                + fx * (1 - fy) * Float(p[i10 + c])
                + (1 - fx) * fy * Float(p[i01 + c])
                + fx * fy * Float(p[i11 + c])
            return UInt8(min(255, max(0, v.rounded())))
        }
        return (chan(0), chan(1), chan(2))
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
        guard let firstCol = cols.first, let lastCol = cols.last, lastCol > firstCol else { return canvas }
        var x0 = firstCol
        var x1 = lastCol
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
        // A small roll makes the outer columns shorter than this window. Those corners are empty and turn white in the JPEG.
        var left = x0
        var right = x1
        var covered = false
        if y1 > y0 {
            for x in x0...x1 where opaque[x] && top[x] <= y0 && bot[x] >= y1 - 1 {
                if !covered { left = x; covered = true }
                right = x
            }
        }
        if covered, right > left + 16 {
            x0 = left
            x1 = right
        }
        let pad = 3
        if x1 - x0 > pad * 2 + 32 {
            x0 += pad
            x1 -= pad
        }
        if y1 - y0 > pad * 2 + 32 {
            y0 += pad
            y1 -= pad
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

    /// Match red, green, and blue on the pixels that land on top of each other.
    /// A scale alone meets the average: shadows on one body stay hot and the highlights go the other way.
    /// Fit a slope and a black level per channel, and only darken, so a highlight is never pushed past what that body recorded.
    private static func balancePair(_ r: inout [UInt8], _ t: inout [UInt8], _ w: Int, _ h: Int) {
        var sumR = [0.0, 0.0, 0.0]
        var sumT = [0.0, 0.0, 0.0]
        var rr = [0.0, 0.0, 0.0]
        var rt = [0.0, 0.0, 0.0]
        var n = 0.0
        for y in stride(from: 0, to: h, by: 4) {
            for x in stride(from: 0, to: w, by: 4) {
                let i = (y * w + x) * 4
                guard r[i + 3] > 32, t[i + 3] > 32 else { continue }
                var usable = true
                for c in 0..<3 {
                    let rv = r[i + c]
                    let tv = t[i + c]
                    if rv < 16 || rv > 240 || tv < 16 || tv > 240 { usable = false }
                }
                if !usable { continue }
                for c in 0..<3 {
                    let rv = Double(r[i + c])
                    let tv = Double(t[i + c])
                    sumR[c] += rv
                    sumT[c] += tv
                    rr[c] += rv * rv
                    rt[c] += rv * tv
                }
                n += 1
            }
        }
        guard n > 200 else { return }
        var slope = [1.0, 1.0, 1.0]
        var offset = [0.0, 0.0, 0.0]
        var onT = [false, false, false]
        var live = [false, false, false]
        for c in 0..<3 {
            guard sumR[c] > 1 else { continue }
            let meanGain = sumT[c] / sumR[c]
            guard meanGain >= 0.40, meanGain <= 2.50 else { continue }
            var g = meanGain
            var b = 0.0
            let det = rr[c] * n - sumR[c] * sumR[c]
            if det > 1 {
                let ag = (rt[c] * n - sumR[c] * sumT[c]) / det
                let ab = (rr[c] * sumT[c] - sumR[c] * rt[c]) / det
                if ag >= 0.50, ag <= 1.80, abs(ab) <= 40 {
                    let mid = meanGain >= 1 ? (128 - ab) / ag : ag * 128 + ab
                    if mid < 127 {
                        g = ag
                        b = ab
                    }
                }
            }
            if abs(meanGain - 1) <= 0.008, abs(b) < 1.5 { continue }
            slope[c] = g
            offset[c] = b
            onT[c] = meanGain >= 1
            live[c] = true
        }
        guard live.contains(true) else { return }
        func line(_ wantT: Bool) -> String {
            (0..<3).map { c in
                guard live[c], onT[c] == wantT else { return "·" }
                return String(format: "×%.3f%+.1f", slope[c], offset[c])
            }.joined(separator: " ")
        }
        let tLine = line(true)
        let rLine = line(false)
        if tLine.contains("×") { print("FXPAN balance T \(tLine)") }
        if rLine.contains("×") { print("FXPAN balance R \(rLine)") }
        curve(&t, slope, offset, onT, live, pullT: true)
        curve(&r, slope, offset, onT, live, pullT: false)
    }

    /// `pullT` maps T down onto R with `(v − offset) / slope`. The other way maps R down onto T.
    private static func curve(_ px: inout [UInt8], _ slope: [Double], _ offset: [Double], _ onT: [Bool], _ live: [Bool], pullT: Bool) {
        for i in stride(from: 0, to: px.count, by: 4) {
            guard px[i + 3] > 32 else { continue }
            for c in 0..<3 where live[c] && onT[c] == pullT {
                let v = Double(px[i + c])
                let out = pullT ? (v - offset[c]) / slope[c] : slope[c] * v + offset[c]
                if out < v {
                    px[i + c] = UInt8(min(255, max(0, out.rounded())))
                }
            }
        }
    }

    /// The coarsest band carries exposure across the seam and must fade out before either frame's edge of the overlap.
    private static func bandCount(overlapPx: Int) -> Int {
        let top = Int(log2(max(1, Double(overlapPx) / 6)).rounded(.down))
        return min(10, max(5, top + 1))
    }

    /// iOS raises a process's memory limit as it allocates, so `os_proc_available_memory`
    /// under-reports what an 8 GB or 12 GB device will actually allow. Gate on installed RAM.
    /// A 4 GB iPad stays on the feather path; the band blend would get the app killed there.
    private static func memoryAllowsBands(w: Int, h: Int) -> Bool {
        let ram = ProcessInfo.processInfo.physicalMemory
        let ok = ram >= 8 * 1024 * 1024 * 1024
        print(String(format: "FXPAN bands ram=%.1fGB canvas=%dx%d %@", Double(ram) / 1_073_741_824, w, h, ok ? "yes" : "no"))
        return ok
    }

    private static func multiband(r: [UInt8], t: [UInt8], w: Int, h: Int, bands: Int, stop: StitchStop?) throws -> [UInt8]? {
        try StitchGate.check(stop)
        let weight = seam(r, t, w, h)
        var out = [UInt8](repeating: 0, count: w * h * 4)
        for c in 0..<3 {
            try StitchGate.check(stop)
            var rc = filledPlane(r, w, h, c)
            var tc = filledPlane(t, w, h, c)
            let blended = try blendPlanes(&rc, &tc, weight, w, h, bands: bands, stop: stop)
            for i in 0..<w * h {
                let o = i * 4
                let ra = r[o + 3] > 32
                let ta = t[o + 3] > 32
                let value: Float
                if ra && ta {
                    let rv = Float(r[o + c])
                    let tv = Float(t[o + c])
                    // The pyramid overshoots past the brighter frame. Keep the photograph's own highlights.
                    value = min(max(rv, tv), max(min(rv, tv), blended[i]))
                } else if ra {
                    value = Float(r[o + c])
                } else if ta {
                    value = Float(t[o + c])
                } else {
                    value = blended[i]
                }
                out[o + c] = UInt8(min(255, max(0, value.rounded())))
            }
        }
        for i in 0..<w * h {
            let a = r[i * 4 + 3] > 32 || t[i * 4 + 3] > 32
            out[i * 4 + 3] = a ? 255 : 0
        }
        return out
    }

    private static func blendPlanes(_ r: inout [Float], _ t: inout [Float], _ wgt: [Float], _ w: Int, _ h: Int, bands: Int, stop: StitchStop?) throws -> [Float] {
        let weights = try gaussPyramid(wgt, w, h, bands: bands, stop: stop)
        var acc = try laplacian(&r, w, h, bands: bands, stop: stop)
        try applyWeight(&acc, weights, invert: false, stop: stop)
        var other = try laplacian(&t, w, h, bands: bands, stop: stop)
        try applyWeight(&other, weights, invert: true, stop: stop)
        for level in 0..<acc.levels.count {
            let n = min(acc.levels[level].count, other.levels[level].count)
            for i in 0..<n { acc.levels[level][i] += other.levels[level][i] }
            other.levels[level] = []
        }
        return try collapse(acc, stop: stop)
    }

    private struct Pyr {
        var levels: [[Float]]
        var sizes: [(Int, Int)]
    }

    private static func gaussPyramid(_ src: [Float], _ w: Int, _ h: Int, bands: Int, stop: StitchStop?) throws -> Pyr {
        var levels = [src]
        var sizes = [(w, h)]
        var cw = w, ch = h
        for _ in 1..<bands {
            try StitchGate.check(stop)
            let (nr, nw, nh) = pyrDown(levels.last!, cw, ch)
            if nw < 8 || nh < 8 { break }
            levels.append(nr)
            sizes.append((nw, nh))
            cw = nw
            ch = nh
        }
        return Pyr(levels: levels, sizes: sizes)
    }

    /// Gaussian pyramid turned into a Laplacian in place, one level at a time, so both frames are never expanded together.
    /// Fine to coarse only: each level subtracts the Gaussian above it, which must not have been converted yet.
    private static func laplacian(_ src: inout [Float], _ w: Int, _ h: Int, bands: Int, stop: StitchStop?) throws -> Pyr {
        var pyr = try gaussPyramid(src, w, h, bands: bands, stop: stop)
        src = []
        let last = pyr.levels.count - 1
        for level in 0..<last {
            try StitchGate.check(stop)
            let up = pyrUp(
                pyr.levels[level + 1],
                pyr.sizes[level + 1].0, pyr.sizes[level + 1].1,
                pyr.sizes[level].0, pyr.sizes[level].1
            )
            var fine = pyr.levels[level]
            pyr.levels[level] = []
            for i in 0..<fine.count { fine[i] -= up[i] }
            pyr.levels[level] = fine
        }
        return pyr
    }

    private static func applyWeight(_ pyr: inout Pyr, _ weights: Pyr, invert: Bool, stop: StitchStop?) throws {
        for level in 0..<pyr.levels.count {
            try StitchGate.check(stop)
            let mask = level < weights.levels.count ? weights.levels[level] : []
            var px = pyr.levels[level]
            pyr.levels[level] = []
            let n = min(px.count, mask.count)
            if invert {
                for i in 0..<n { px[i] *= 1 - min(1, max(0, mask[i])) }
            } else {
                for i in 0..<n { px[i] *= min(1, max(0, mask[i])) }
            }
            pyr.levels[level] = px
        }
    }

    private static func collapse(_ pyr: Pyr, stop: StitchStop?) throws -> [Float] {
        let last = pyr.levels.count - 1
        var acc = pyr.levels[last]
        if last == 0 { return acc }
        for level in stride(from: last - 1, through: 0, by: -1) {
            try StitchGate.check(stop)
            acc = pyrUp(acc, pyr.sizes[level + 1].0, pyr.sizes[level + 1].1, pyr.sizes[level].0, pyr.sizes[level].1)
            let fine = pyr.levels[level]
            let n = min(acc.count, fine.count)
            for i in 0..<n { acc[i] += fine[i] }
        }
        return acc
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
        var distR = [Int32](repeating: 1_000_000, count: n)
        var distT = [Int32](repeating: 1_000_000, count: n)
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

    private static func chamfer(_ d: inout [Int32], _ w: Int, _ h: Int) {
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

    /// Empty warp pixels are black. A band pyramid treats that cliff as detail and the bright side overshoots white.
    /// Continue the last real pixel across the gap so the bands only see the photograph.
    private static func filledPlane(_ px: [UInt8], _ w: Int, _ h: Int, _ c: Int) -> [Float] {
        var o = [Float](repeating: -1, count: w * h)
        for i in 0..<w * h where px[i * 4 + 3] > 32 {
            o[i] = Float(px[i * 4 + c])
        }
        for y in 0..<h {
            var carry: Float = -1
            let row = y * w
            for x in 0..<w {
                let i = row + x
                if o[i] >= 0 { carry = o[i] }
                else if carry >= 0 { o[i] = carry }
            }
            carry = -1
            for x in stride(from: w - 1, through: 0, by: -1) {
                let i = row + x
                if o[i] >= 0 { carry = o[i] }
                else if carry >= 0 { o[i] = carry }
            }
        }
        for x in 0..<w {
            var carry: Float = -1
            for y in 0..<h {
                let i = y * w + x
                if o[i] >= 0 { carry = o[i] }
                else if carry >= 0 { o[i] = carry }
            }
            carry = -1
            for y in stride(from: h - 1, through: 0, by: -1) {
                let i = y * w + x
                if o[i] >= 0 { carry = o[i] }
                else if carry >= 0 { o[i] = carry }
            }
        }
        for i in 0..<o.count where o[i] < 0 { o[i] = 0 }
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
        return blur5(tmp, tw, th, gain: 4)
    }

    private static func blur5(_ src: [Float], _ w: Int, _ h: Int, gain: Float = 1) -> [Float] {
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
        if gain != 1 {
            for i in 0..<dst.count { dst[i] *= gain }
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
