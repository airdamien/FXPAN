import CoreGraphics
import Foundation
import ImageIO

/// Color, fringe, and flat measured from the printed sheet. Gains multiply that body so it matches the reference body.
struct PlateBody: Codable, Equatable, Identifiable {
    var serial: String
    var model: String
    var taken: Date
    var reference: String = ""
    var gainR: Float = 1
    var gainG: Float = 1
    var gainB: Float = 1
    var caR: Float = 0
    var caB: Float = 0
    var flatW: Int = 0
    var flatH: Int = 0
    var flat: [Float] = []
    var id: String { serial }

    var hasFringe: Bool { abs(caR) > 0.0004 || abs(caB) > 0.0004 }
    var hasFlat: Bool { flatW > 1 && flatH > 1 && flat.count == flatW * flatH && Self.isShading(flat, flatW, flatH) }

    /// A lens or plate shade changes slowly. The printed grid and the crosses do not, and must not be stored.
    static func isShading(_ flat: [Float], _ w: Int, _ h: Int) -> Bool {
        guard w > 1, h > 1, flat.count == w * h else { return false }
        var jump: Float = 0
        var n: Float = 0
        var big: Float = 0
        for y in 0..<h {
            for x in 0..<(w - 1) {
                let d = abs(flat[y * w + x] - flat[y * w + x + 1])
                jump += d
                n += 1
                if d > 0.12 { big += 1 }
            }
            if y + 1 < h {
                for x in 0..<w {
                    let d = abs(flat[y * w + x] - flat[(y + 1) * w + x])
                    jump += d
                    n += 1
                    if d > 0.12 { big += 1 }
                }
            }
        }
        guard n > 0 else { return false }
        return jump / n < 0.02 && big / n < 0.03
    }

    func line() -> String {
        var parts: [String] = []
        let referenceBody = reference == serial && abs(gainR - 1) < 0.004 && abs(gainG - 1) < 0.004 && abs(gainB - 1) < 0.004
        if referenceBody {
            parts.append("reference")
        } else if abs(gainR - 1) > 0.004 || abs(gainG - 1) > 0.004 || abs(gainB - 1) > 0.004 {
            parts.append(String(format: "color %+.1f %+.1f %+.1f%%", (gainR - 1) * 100, (gainG - 1) * 100, (gainB - 1) * 100))
        }
        if hasFringe {
            parts.append(String(format: "fringe %+.2f %+.2f%%", caR * 100, caB * 100))
        }
        if hasFlat, let fall = cornerFall() {
            parts.append(String(format: "flat corner %+.0f%%", fall * 100))
        }
        if parts.isEmpty { return "No sheet yet" }
        return parts.joined(separator: " · ")
    }

    /// A body row with the measurements still in it. An empty row left after a clear does not count.
    var measured: Bool {
        if hasFringe || hasFlat { return true }
        if abs(gainR - 1) > 0.004 || abs(gainG - 1) > 0.004 || abs(gainB - 1) > 0.004 { return true }
        return reference == serial && !serial.isEmpty
    }

    func cornerFall() -> Float? {
        guard hasFlat else { return nil }
        let corners = [flat[0], flat[flatW - 1], flat[(flatH - 1) * flatW], flat[flatH * flatW - 1]]
        let edge = corners.reduce(0, +) / Float(corners.count)
        return edge - 1
    }
}

enum PlateBook {
    static let guide = "Step back to about 3 m, ten feet, until the whole sheet is sharp. A 180mm at closest focus sees about a foot of it and will not focus if you walk in. At ten feet the 24×16 sheet fills the D800, and the D7000 sees the middle. Keep the lamp's reflection off the paper. The gray should sit near the middle of the meter."

    private struct File: Codable {
        var on: Bool
        var bodies: [PlateBody]
    }

    private static let lock = NSLock()
    private static var cache: File?

    static var isOn: Bool { snapshot().on }

    static func forget() {
        lock.lock()
        cache = nil
        lock.unlock()
    }

    static func setOn(_ on: Bool) {
        lock.lock()
        defer { lock.unlock() }
        var file = loadUnlocked()
        file.on = on
        writeUnlocked(file)
    }

    static func bodies() -> [PlateBody] { snapshot().bodies }

    /// Drop every saved body. An empty row was still counting as saved.
    static func clearMeasurements() {
        lock.lock()
        defer { lock.unlock() }
        var file = loadUnlocked()
        file.bodies = []
        writeUnlocked(file)
    }

    static func correct(_ image: CGImage, url: URL) -> CGImage {
        guard isOn, image.width >= 32, image.height >= 32 else { return image }
        let who = NoiseBook.identity(url)
        guard let body = match(serial: who.serial, model: who.model) else { return image }
        let quietGain = abs(body.gainR - 1) < 0.008 && abs(body.gainG - 1) < 0.008 && abs(body.gainB - 1) < 0.008
        let quietCA = abs(body.caR) < 0.0008 && abs(body.caB) < 0.0008
        if quietGain && quietCA && !body.hasFlat { return image }
        return paint(image, body) ?? image
    }

    static func update(_ serial: String, model: String, _ edit: (inout PlateBody) -> Void) {
        guard !serial.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var file = loadUnlocked()
        var body = file.bodies.first { same($0.serial, serial) } ?? PlateBody(serial: serial, model: model, taken: Date())
        body.model = model.isEmpty ? body.model : model
        body.taken = Date()
        edit(&body)
        file.bodies.removeAll { same($0.serial, serial) }
        file.bodies.append(body)
        writeUnlocked(file)
    }

    private static func paint(_ image: CGImage, _ body: PlateBody) -> CGImage? {
        let w = image.width
        let h = image.height
        let row = w * 4
        let bytes = row * h
        guard bytes > 0, bytes < 500_000_000 else { return image }
        guard let src = malloc(bytes), let dst = malloc(bytes) else { return image }
        defer { free(src); free(dst) }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: src, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let inn = src.assumingMemoryBound(to: UInt8.self)
        let out = dst.assumingMemoryBound(to: UInt8.self)
        let cx = Float(w - 1) * 0.5
        let cy = Float(h - 1) * 0.5
        let fw = body.flatW
        let fh = body.flatH
        let flat = body.flat
        let useFlat = body.hasFlat
        for y in 0..<h {
            for x in 0..<w {
                let dx = Float(x) - cx
                let dy = Float(y) - cy
                let r = sample(inn, w, h, row, cx + dx * (1 + body.caR), cy + dy * (1 + body.caR), 0)
                let g = sample(inn, w, h, row, Float(x), Float(y), 1)
                let b = sample(inn, w, h, row, cx + dx * (1 + body.caB), cy + dy * (1 + body.caB), 2)
                let shade = useFlat ? flatAt(flat, fw, fh, x, y, w, h) : 1
                let o = y * row + x * 4
                out[o] = byte(r * body.gainR * shade)
                out[o + 1] = byte(g * body.gainG * shade)
                out[o + 2] = byte(b * body.gainB * shade)
                out[o + 3] = inn[o + 3]
            }
        }
        guard let outCtx = CGContext(
            data: dst, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }
        return outCtx.makeImage()
    }

    private static func sample(_ px: UnsafePointer<UInt8>, _ w: Int, _ h: Int, _ row: Int, _ x: Float, _ y: Float, _ c: Int) -> Float {
        let x = min(Float(w - 1), max(0, x))
        let y = min(Float(h - 1), max(0, y))
        let x0 = Int(x)
        let y0 = Int(y)
        let x1 = min(w - 1, x0 + 1)
        let y1 = min(h - 1, y0 + 1)
        let fx = x - Float(x0)
        let fy = y - Float(y0)
        let a = Float(px[y0 * row + x0 * 4 + c])
        let b = Float(px[y0 * row + x1 * 4 + c])
        let d = Float(px[y1 * row + x0 * 4 + c])
        let e = Float(px[y1 * row + x1 * 4 + c])
        return a + (b - a) * fx + (d - a) * fy + (a - b - d + e) * fx * fy
    }

    private static func flatAt(_ flat: [Float], _ fw: Int, _ fh: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int) -> Float {
        let fx = (Float(x) + 0.5) / Float(w) * Float(fw) - 0.5
        let fy = (Float(y) + 0.5) / Float(h) * Float(fh) - 0.5
        let x0 = max(0, min(fw - 1, Int(floor(fx))))
        let y0 = max(0, min(fh - 1, Int(floor(fy))))
        let x1 = min(fw - 1, x0 + 1)
        let y1 = min(fh - 1, y0 + 1)
        let tx = min(1, max(0, fx - Float(x0)))
        let ty = min(1, max(0, fy - Float(y0)))
        let a = flat[y0 * fw + x0]
        let b = flat[y0 * fw + x1]
        let d = flat[y1 * fw + x0]
        let e = flat[y1 * fw + x1]
        return a + (b - a) * tx + (d - a) * ty + (a - b - d + e) * tx * ty
    }

    private static func byte(_ v: Float) -> UInt8 {
        UInt8(min(255, max(0, v + 0.5)))
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        NoiseBook.sameSerial(a, b)
    }

    private static func snapshot() -> File {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    private static func loadUnlocked() -> File {
        if let cache { return cache }
        let url = Disk.support.appendingPathComponent("plate.json")
        var file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File(on: false, bodies: [])
        var dropped = false
        let before = file.bodies.count
        file.bodies.removeAll { !$0.measured }
        if file.bodies.count != before { dropped = true }
        for index in file.bodies.indices where file.bodies[index].flatW > 1 && !PlateBody.isShading(file.bodies[index].flat, file.bodies[index].flatW, file.bodies[index].flatH) {
            file.bodies[index].flat = []
            file.bodies[index].flatW = 0
            file.bodies[index].flatH = 0
            dropped = true
        }
        cache = file
        if dropped { writeUnlocked(file) }
        return file
    }

    private static func writeUnlocked(_ file: File) {
        cache = file
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: Disk.support.appendingPathComponent("plate.json"), options: .atomic)
        CloudShelf.push("plate.json")
    }

    private static func match(serial: String, model: String) -> PlateBody? {
        let saved = snapshot().bodies
        let clean = PTP.usable(serial)
        if !clean.isEmpty {
            return saved.first { same($0.serial, clean) }
        }
        let name = model.lowercased()
        guard !name.isEmpty else { return nil }
        let hits = saved.filter { body in
            let theirs = body.model.lowercased()
            return !theirs.isEmpty && (name.contains(theirs) || theirs.contains(name))
        }
        return hits.count == 1 ? hits[0] : nil
    }
}

enum PlateField {
    struct Means {
        var r: Float
        var g: Float
        var b: Float
        var wave: Float
        var hi: Float { max(r, max(g, b)) }
        var lo: Float { min(r, min(g, b)) }
        /// Flat and not clipped. A strong cast still counts: that cast is the color the plate is measuring. A patch that is basically one channel does not.
        var neutral: Bool { hi - lo < 0.75 * max(hi, 0.02) && lo > 0.02 && hi < 0.92 && wave < 0.05 }
    }

    /// True when the paper was found inside the frame and the glass around it can be left out.
    static func trimmedDoor(_ image: CGImage) -> Bool {
        guard let raster = Raster.make(image, maxEdge: 420) else { return false }
        let sheet = raster.sheet()
        return sheet.width * sheet.height < CGFloat(raster.w * raster.h) * 0.92
    }

    /// The grayest window on the sheet. A cross in the middle loses to a clean patch of the gray.
    static func gray(_ image: CGImage) -> Means? {
        guard let raster = Raster.make(image, maxEdge: 480) else { return nil }
        let boxes = raster.windows(in: raster.sheet())
        var best: Means?
        var bestWave = Float.greatestFiniteMagnitude
        var bestSpread = Float.greatestFiniteMagnitude
        for box in boxes {
            let mean = raster.mean(box.0, box.1, box.2, box.3)
            let spread = mean.hi - mean.lo
            if mean.wave < bestWave - 0.008 || (abs(mean.wave - bestWave) <= 0.008 && spread < bestSpread) {
                bestWave = mean.wave
                bestSpread = spread
                best = mean
            }
        }
        return best
    }

    /// Lateral scale of red and blue against green. Positive means that channel grows toward the corner.
    static func fringe(_ image: CGImage) -> (caR: Float, caB: Float, edges: Int)? {
        guard let raster = Raster.make(image, maxEdge: 900) else { return nil }
        var xs: [Float] = []
        var sr: [Float] = []
        var sb: [Float] = []
        func take(_ pos: Float, _ half: Float, _ shiftR: Float, _ shiftB: Float) {
            let norm = (pos - half) / half
            guard abs(norm) > 0.08, abs(shiftR) < 4, abs(shiftB) < 4 else { return }
            xs.append(norm)
            sr.append(shiftR / half)
            sb.append(shiftB / half)
        }
        let w = raster.w
        let h = raster.h
        let sheet = sheetBox(image, raster)
        let xLo = max(3, Int(sheet.minX))
        let xHi = min(w - 3, Int(sheet.maxX))
        let yLo = max(2, Int(sheet.minY))
        let yHi = min(h - 2, Int(sheet.maxY))
        var y = yLo
        while y < yHi {
            var x = xLo
            while x < xHi {
                if let hit = raster.shiftX(x, y) {
                    take(Float(x), Float(w) * 0.5, hit.r, hit.b)
                    x += 6
                }
                x += 1
            }
            y += 3
        }
        var x = xLo
        while x < xHi {
            var yy = yLo
            while yy < yHi {
                if let hit = raster.shiftY(x, yy) {
                    take(Float(yy), Float(h) * 0.5, hit.r, hit.b)
                    yy += 6
                }
                yy += 1
            }
            x += 3
        }
        guard xs.count >= 40 else { return nil }
        let caR = slope(xs, sr)
        let caB = slope(xs, sb)
        guard abs(caR) < 0.04, abs(caB) < 0.04 else { return nil }
        var err: Float = 0
        for i in 0..<xs.count {
            err += abs(sr[i] - caR * xs[i])
        }
        if err / Float(xs.count) > 0.004 { return nil }
        return (caR, caB, xs.count)
    }

    /// Four aims of the gray. A cell counts only where that frame was flat gray, so the rules and the room drop out.
    static func flat(_ images: [CGImage]) -> (w: Int, h: Int, values: [Float])? {
        let cols = 48
        let rows = 32
        let grids = images.compactMap { image -> [Raster.Cell]? in
            guard let raster = Raster.make(image, maxEdge: 480) else { return nil }
            return raster.cells(across: cols, down: rows, sheet: raster.sheet())
        }
        guard let first = grids.first, grids.count >= 3, grids.allSatisfy({ $0.count == first.count }) else { return nil }
        let n = first.count
        var level = [Float](repeating: 0, count: n)
        var known = [Bool](repeating: false, count: n)
        for i in 0..<n {
            let stack = grids.compactMap { $0[i].ok ? Optional($0[i].luma) : nil }.sorted()
            guard stack.count >= 1, let mid = stack.dropFirst(stack.count / 2).first, mid > 0.03 else { continue }
            level[i] = mid
            known[i] = true
        }
        let seen = known.filter { $0 }.count
        guard seen >= n / 5 else { return nil }
        let ranked = level.enumerated().compactMap { known[$0.offset] ? $0.element : nil }.sorted()
        guard let ref = ranked.dropFirst(ranked.count / 2).first, ref > 0.03 else { return nil }
        var filled = known
        var field = level
        for _ in 0..<6 {
            var next = field
            var nextKnown = filled
            for y in 0..<rows {
                for x in 0..<cols {
                    let i = y * cols + x
                    if filled[i] { continue }
                    var sum: Float = 0
                    var cn: Float = 0
                    for dy in -1...1 {
                        for dx in -1...1 where dx != 0 || dy != 0 {
                            let xx = x + dx
                            let yy = y + dy
                            guard xx >= 0, yy >= 0, xx < cols, yy < rows else { continue }
                            let j = yy * cols + xx
                            if filled[j] {
                                sum += field[j]
                                cn += 1
                            }
                        }
                    }
                    if cn > 0 {
                        next[i] = sum / cn
                        nextKnown[i] = true
                    }
                }
            }
            field = next
            filled = nextKnown
        }
        var out = [Float](repeating: 1, count: n)
        for i in 0..<n where filled[i] {
            out[i] = min(1.35, max(0.7, ref / max(field[i], 0.02)))
        }
        guard PlateBody.isShading(out, cols, rows) else { return nil }
        return (cols, rows, out)
    }

    /// Sheet bounds in the working raster. The search itself stays on a small image.
    private static func sheetBox(_ image: CGImage, _ raster: Raster) -> CGRect {
        guard raster.w > 520, let small = Raster.make(image, maxEdge: 360) else { return raster.sheet() }
        let found = small.sheet()
        let sx = CGFloat(raster.w) / CGFloat(small.w)
        let sy = CGFloat(raster.h) / CGFloat(small.h)
        return CGRect(x: found.minX * sx, y: found.minY * sy, width: found.width * sx, height: found.height * sy)
    }

    private static func slope(_ xs: [Float], _ ys: [Float]) -> Float {
        var sxx: Float = 0
        var sxy: Float = 0
        for i in 0..<xs.count {
            sxx += xs[i] * xs[i]
            sxy += xs[i] * ys[i]
        }
        guard sxx > 1 else { return 0 }
        return sxy / sxx
    }

    private struct Raster {
        var w: Int
        var h: Int
        var px: [UInt8]

        static func make(_ image: CGImage, maxEdge: Int) -> Raster? {
            let edge = max(image.width, image.height)
            let scale = min(1, Float(maxEdge) / Float(max(edge, 1)))
            let w = max(16, Int((Float(image.width) * scale).rounded()))
            let h = max(16, Int((Float(image.height) * scale).rounded()))
            let row = w * 4
            let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let ctx = CGContext(
                data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ), let data = ctx.data else { return nil }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            let raw = data.assumingMemoryBound(to: UInt8.self)
            return Raster(w: w, h: h, px: Array(UnsafeBufferPointer(start: raw, count: row * h)))
        }

        /// The printed sheet. Neutral paper, closed across the black rules, prefers the region that holds both the gray and the white grid. The full frame when the sheet already fills it.
        func sheet() -> CGRect {
            let full = CGRect(x: 0, y: 0, width: w, height: h)
            let n = w * h
            guard n > 64 else { return full }
            var paper = [Bool](repeating: false, count: n)
            for i in 0..<n {
                let tone = toneAt(i)
                paper[i] = tone.l > 88 && tone.chroma < 42
            }
            let radius = max(2, min(w, h) / 90)
            let solid = close(paper, radius: radius)
            var seen = [Bool](repeating: false, count: n)
            var stack: [Int] = []
            var bestBoth: (score: Int, rect: CGRect)?
            var bestGray: (score: Int, rect: CGRect)?
            func push(_ j: Int) {
                if solid[j], !seen[j] {
                    seen[j] = true
                    stack.append(j)
                }
            }
            for start in 0..<n where solid[start] && !seen[start] {
                seen[start] = true
                stack.append(start)
                var area = 0
                var white = 0
                var gray = 0
                var minX = w
                var minY = h
                var maxX = 0
                var maxY = 0
                while let i = stack.popLast() {
                    let x = i % w
                    let y = i / w
                    area += 1
                    if x < minX { minX = x }
                    if y < minY { minY = y }
                    if x > maxX { maxX = x }
                    if y > maxY { maxY = y }
                    let tone = toneAt(i)
                    if tone.chroma < 42 {
                        if tone.l > 205 { white += 1 }
                        else if tone.l > 115 && tone.l < 198 { gray += 1 }
                    }
                    if x > 0 { push(i - 1) }
                    if x + 1 < w { push(i + 1) }
                    if y > 0 { push(i - w) }
                    if y + 1 < h { push(i + w) }
                }
                guard area > n / 25 else { continue }
                let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                let both = min(white, gray)
                if both > n / 40, bestBoth == nil || both > bestBoth!.score {
                    bestBoth = (both, rect)
                }
                if gray > n / 30, bestGray == nil || gray > bestGray!.score {
                    bestGray = (gray, rect)
                }
            }
            guard var rect = bestBoth?.rect ?? bestGray?.rect else { return full }
            if rect.width * rect.height > CGFloat(n) * 0.94 { return full }
            rect = rect.insetBy(dx: rect.width * 0.02, dy: rect.height * 0.02)
            rect = rect.intersection(full)
            if rect.width < 32 || rect.height < 32 { return full }
            return rect
        }

        func windows(in rect: CGRect) -> [(Int, Int, Int, Int)] {
            var out: [(Int, Int, Int, Int)] = []
            let ww = rect.width * 0.42
            let hh = rect.height * 0.42
            guard ww > 8, hh > 8 else {
                return [(0, 0, w, h)]
            }
            for j in 0..<3 {
                for i in 0..<3 {
                    let x = rect.minX + (rect.width - ww) * CGFloat(i) / 2
                    let y = rect.minY + (rect.height - hh) * CGFloat(j) / 2
                    out.append((Int(x), Int(y), Int(x + ww), Int(y + hh)))
                }
            }
            return out
        }

        private func toneAt(_ i: Int) -> (l: Int, chroma: Int) {
            let o = i * 4
            let r = Int(px[o])
            let g = Int(px[o + 1])
            let b = Int(px[o + 2])
            let hi = max(r, max(g, b))
            let lo = min(r, min(g, b))
            return ((r + g + g + b) / 4, hi - lo)
        }

        private func close(_ src: [Bool], radius: Int) -> [Bool] {
            erode(dilate(src, radius), radius)
        }

        private func dilate(_ src: [Bool], _ radius: Int) -> [Bool] {
            var out = [Bool](repeating: false, count: src.count)
            for y in 0..<h {
                for x in 0..<w {
                    var on = false
                    for yy in max(0, y - radius)...min(h - 1, y + radius) where !on {
                        let row = yy * w
                        for xx in max(0, x - radius)...min(w - 1, x + radius) where src[row + xx] {
                            on = true
                            break
                        }
                    }
                    out[y * w + x] = on
                }
            }
            return out
        }

        private func erode(_ src: [Bool], _ radius: Int) -> [Bool] {
            var out = [Bool](repeating: false, count: src.count)
            for y in 0..<h {
                for x in 0..<w {
                    var on = true
                    for yy in max(0, y - radius)...min(h - 1, y + radius) where on {
                        let row = yy * w
                        for xx in max(0, x - radius)...min(w - 1, x + radius) where !src[row + xx] {
                            on = false
                            break
                        }
                    }
                    out[y * w + x] = on
                }
            }
            return out
        }

        func mean(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int) -> Means {
            var sr: Float = 0, sg: Float = 0, sb: Float = 0, sl: Float = 0, sl2: Float = 0, n: Float = 0
            var y = max(0, y0)
            let yEnd = min(h, y1)
            let xStart = max(0, x0)
            let xEnd = min(w, x1)
            while y < yEnd {
                var x = xStart
                while x < xEnd {
                    let i = (y * w + x) * 4
                    let r = lin(px[i])
                    let g = lin(px[i + 1])
                    let b = lin(px[i + 2])
                    let l = 0.25 * r + 0.5 * g + 0.25 * b
                    sr += r
                    sg += g
                    sb += b
                    sl += l
                    sl2 += l * l
                    n += 1
                    x += 2
                }
                y += 2
            }
            guard n > 0 else { return Means(r: 0, g: 0, b: 0, wave: 1) }
            let meanL = sl / n
            let wave = sqrt(max(0, sl2 / n - meanL * meanL))
            return Means(r: sr / n, g: sg / n, b: sb / n, wave: wave)
        }

        struct Cell {
            var luma: Float
            var ok: Bool
        }

        func cells(across cols: Int, down rows: Int, sheet: CGRect) -> [Cell] {
            var out = [Cell](repeating: Cell(luma: 0, ok: false), count: cols * rows)
            for gy in 0..<rows {
                for gx in 0..<cols {
                    let x0 = gx * w / cols
                    let x1 = (gx + 1) * w / cols
                    let y0 = gy * h / rows
                    let y1 = (gy + 1) * h / rows
                    let inside = sheet.contains(CGPoint(x: (x0 + x1) / 2, y: (y0 + y1) / 2))
                    let m = mean(x0, y0, x1, y1)
                    out[gy * cols + gx] = Cell(luma: 0.25 * m.r + 0.5 * m.g + 0.25 * m.b, ok: inside && m.neutral)
                }
            }
            return out
        }

        func shiftX(_ x: Int, _ y: Int) -> (r: Float, b: Float)? {
            shift(x, y, step: 4)
        }

        func shiftY(_ x: Int, _ y: Int) -> (r: Float, b: Float)? {
            shift(x, y, step: w * 4)
        }

        private func shift(_ x: Int, _ y: Int, step: Int) -> (r: Float, b: Float)? {
            let i = (y * w + x) * 4
            guard i - step * 2 >= 0, i + step * 2 < px.count else { return nil }
            let g0 = Int(px[i - step + 1])
            let g1 = Int(px[i + step + 1])
            guard abs(g1 - g0) > 28 else { return nil }
            var wr: Float = 0, wg: Float = 0, wb: Float = 0
            var sr: Float = 0, sg: Float = 0, sb: Float = 0
            for k in -2...2 {
                let p = i + k * step
                guard p - step >= 0, p + step < px.count else { return nil }
                let dr = Float(abs(Int(px[p + step]) - Int(px[p - step])))
                let dg = Float(abs(Int(px[p + step + 1]) - Int(px[p - step + 1])))
                let db = Float(abs(Int(px[p + step + 2]) - Int(px[p - step + 2])))
                guard dg > 8 else { continue }
                let at = Float(k)
                wr += dr; wg += dg; wb += db
                sr += at * dr; sg += at * dg; sb += at * db
            }
            guard wg > 20, wr > 12, wb > 12 else { return nil }
            return (sr / wr - sg / wg, sb / wb - sg / wg)
        }

        private func lin(_ u: UInt8) -> Float {
            let x = Float(u) / 255
            return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
    }
}

enum PlateJob {
    case color, fringe, flat
}

/// Frames held between the four flat shots. The run is paced by the user, so this lives across button presses.
final class PlateScratch {
    var shots: [Role: [CGImage]] = [:]
}
