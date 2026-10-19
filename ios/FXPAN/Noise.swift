import Accelerate
import CoreGraphics
import Foundation
import ImageIO

/// One measured frame. Means and variances are linear light, so variance = a × mean + b is the shot-plus-read model.
struct NoiseSample: Codable, Equatable {
    var iso: Int
    var shutter: String
    var meanR: Float
    var meanG: Float
    var meanB: Float
    var varR: Float
    var varG: Float
    var varB: Float
}

struct NoiseFit: Codable, Equatable {
    var aR: Float
    var bR: Float
    var aG: Float
    var bG: Float
    var aB: Float
    var bB: Float

    func scaled(_ rel: Float) -> NoiseFit {
        let r = min(8, max(0.25, rel))
        return NoiseFit(aR: aR * r, bR: bR * r * r, aG: aG * r, bG: bG * r * r, aB: aB * r, bB: bB * r * r)
    }

    func sigma(at y: Float) -> Float {
        let r = sqrt(max(0, aR * y + bR))
        let g = sqrt(max(0, aG * y + bG))
        let b = sqrt(max(0, aB * y + bB))
        return max(r, g, b)
    }
}

struct NoiseISO: Codable, Equatable {
    var iso: Int
    var fit: NoiseFit
}

struct NoiseBody: Codable, Equatable, Identifiable {
    var serial: String
    var model: String
    var taken: Date
    var samples: [NoiseSample]
    var fits: [NoiseISO]
    var id: String { serial }

    func nearest(_ iso: Int) -> NoiseISO? {
        guard iso > 0, !fits.isEmpty else { return nil }
        return fits.min { lhs, rhs in
            abs(log(Double(lhs.iso)) - log(Double(iso))) < abs(log(Double(rhs.iso)) - log(Double(iso)))
        }
    }

    var quietest: NoiseISO? { fits.min { $0.iso < $1.iso } }

    /// True when the high ISO really is noisier than the low one, so the reduction has something to follow.
    func rises() -> Bool {
        let ordered = fits.sorted { $0.iso < $1.iso }
        guard let lo = ordered.first, let hi = ordered.last, lo.iso != hi.iso else { return false }
        let s0 = lo.fit.sigma(at: 0.18)
        let s1 = hi.fit.sigma(at: 0.18)
        return s1 > s0 * 1.15 && s1 > 0.004
    }

    func line() -> String {
        let ordered = fits.sorted { $0.iso < $1.iso }
        guard let lo = ordered.first, let hi = ordered.last else { return "No fit" }
        let s0 = lo.fit.sigma(at: 0.18)
        let s1 = hi.fit.sigma(at: 0.18)
        return "ISO \(lo.iso) to \(hi.iso) · σ \(String(format: "%.3f", s0)) to \(String(format: "%.3f", s1)) · \(samples.count) frames"
    }
}

struct NoiseGrab {
    var image: CGImage
    var iso: Int
    var serial: String
    var model: String
}

enum NoiseBook {
    private struct File: Codable {
        var on: Bool
        var bodies: [NoiseBody]
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

    static func bodies() -> [NoiseBody] { snapshot().bodies }

    static func save(_ incoming: [NoiseBody]) {
        lock.lock()
        defer { lock.unlock() }
        var file = loadUnlocked()
        for body in incoming {
            file.bodies.removeAll { $0.serial == body.serial }
            file.bodies.append(body)
        }
        writeUnlocked(file)
    }

    static func make(serial: String, model: String, samples: [NoiseSample]) -> NoiseBody {
        let isos = Set(samples.map(\.iso)).filter { $0 > 0 }.sorted()
        let fits = isos.map { iso -> NoiseISO in
            let rows = samples.filter { $0.iso == iso }
            return NoiseISO(
                iso: iso,
                fit: NoiseFit(
                    aR: slope(rows.map(\.meanR), rows.map(\.varR)).a,
                    bR: slope(rows.map(\.meanR), rows.map(\.varR)).b,
                    aG: slope(rows.map(\.meanG), rows.map(\.varG)).a,
                    bG: slope(rows.map(\.meanG), rows.map(\.varG)).b,
                    aB: slope(rows.map(\.meanB), rows.map(\.varB)).a,
                    bB: slope(rows.map(\.meanB), rows.map(\.varB)).b
                )
            )
        }
        return NoiseBody(serial: serial, model: model, taken: Date(), samples: samples, fits: fits)
    }

    static func caption(url: URL?) -> String {
        guard let url else { return "No file" }
        let facts = facts(url)
        guard let body = match(serial: facts.serial, model: facts.model) else {
            return "No profile for this body yet. Run it from System, Noise."
        }
        if facts.iso == 0 { return "\(body.model) \(body.serial). This file has no ISO, so the reduction stays off." }
        return "\(body.model) \(body.serial) · \(body.line())"
    }

    /// Chroma first, a lighter touch on luma, a little of the residual left in so the frame does not go plastic.
    static func reduce(_ image: CGImage, url: URL) -> CGImage {
        guard isOn, image.width >= 32, image.height >= 32 else { return image }
        let facts = facts(url)
        guard facts.iso > 0, let body = match(serial: facts.serial, model: facts.model) else { return image }
        guard let hit = body.nearest(facts.iso), let base = body.quietest?.fit else { return image }
        let rel = Float(facts.iso) / Float(max(hit.iso, 1))
        let fit = hit.fit.scaled(rel)
        let mid = amount(fit, base, y: 0.18)
        let dark = amount(fit, base, y: 0.03)
        if mid < 0.04 && dark < 0.04 { return image }
        return paint(image, mid: mid, dark: dark) ?? image
    }

    private static func amount(_ fit: NoiseFit, _ base: NoiseFit, y: Float) -> Float {
        let s = fit.sigma(at: y)
        let z = base.sigma(at: y)
        if s < 0.001 || z < 0.001 { return 0 }
        return min(0.92, max(0, (s / z - 1.08) / 4.2))
    }

    private static func slope(_ xs: [Float], _ ys: [Float]) -> (a: Float, b: Float) {
        let n = Float(xs.count)
        guard n >= 2, xs.count == ys.count else { return (0, max(0, ys.first ?? 0)) }
        var sx: Float = 0, sy: Float = 0, sxx: Float = 0, sxy: Float = 0
        for i in 0..<xs.count {
            sx += xs[i]
            sy += ys[i]
            sxx += xs[i] * xs[i]
            sxy += xs[i] * ys[i]
        }
        let den = n * sxx - sx * sx
        if abs(den) < 1e-8 { return (0, max(0, sy / n)) }
        let a = max(0, (n * sxy - sx * sy) / den)
        let b = max(0, (sy - a * sx) / n)
        return (a, b)
    }

    private static func snapshot() -> File {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked()
    }

    private static func loadUnlocked() -> File {
        if let cache { return cache }
        let url = Disk.support.appendingPathComponent("noise.json")
        let file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File(on: false, bodies: [])
        cache = file
        return file
    }

    private static func writeUnlocked(_ file: File) {
        cache = file
        let url = Disk.support.appendingPathComponent("noise.json")
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
        CloudShelf.push("noise.json")
    }

    static func sameSerial(_ a: String, _ b: String) -> Bool {
        let left = PTP.usable(a)
        let right = PTP.usable(b)
        if left.isEmpty || right.isEmpty { return false }
        if left.compare(right, options: .caseInsensitive) == .orderedSame { return true }
        let lz = left.drop { $0 == "0" }
        let rz = right.drop { $0 == "0" }
        return !lz.isEmpty && lz.compare(rz, options: .caseInsensitive) == .orderedSame
    }

    private static func match(serial: String, model: String) -> NoiseBody? {
        let saved = snapshot().bodies
        let clean = PTP.usable(serial)
        if !clean.isEmpty {
            return saved.first { sameSerial($0.serial, clean) }
        }
        let fileModel = model.lowercased()
        guard !fileModel.isEmpty else { return nil }
        let hits = saved.filter { body in
            let name = body.model.lowercased()
            return !name.isEmpty && (fileModel.contains(name) || name.contains(fileModel))
        }
        return hits.count == 1 ? hits[0] : nil
    }

    static func identity(_ url: URL) -> (iso: Int, serial: String, model: String) {
        facts(url)
    }

    private static func facts(_ url: URL) -> (iso: Int, serial: String, model: String) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) else { return (0, "", "") }
        var iso = 0
        var serial = ""
        var model = ""
        func walk(_ any: Any, key: String) {
            let dict = any as? NSDictionary
            if let dict {
                for key in dict.allKeys {
                    let name = (key as? String) ?? String(describing: key)
                    if let value = dict[key] { walk(value, key: name) }
                }
                return
            }
            let list = any as? [Any] ?? (any as? NSArray).map { Array($0) }
            if let list {
                guard iso == 0, isoKeys.contains(key), let n = whole(list.first), n > 20, n < 409600 else { return }
                iso = n
                return
            }
            if iso == 0, isoKeys.contains(key), let n = whole(any), n > 20, n < 409600 {
                iso = n
            }
            if model.isEmpty, key == "Model", let text = any as? String {
                model = text
            }
            guard serial.isEmpty, serialKeys.contains(key), let text = any as? String else { return }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !PTP.usable(trimmed).isEmpty else { return }
            serial = trimmed
        }
        walk(props, key: "")
        return (iso, serial, model)
    }

    private static func whole(_ any: Any?) -> Int? {
        switch any {
        case let n as NSNumber: return n.intValue
        case let n as Int: return n
        case let n as Double: return Int(n)
        default: return nil
        }
    }

    private static let serialKeys: Set<String> = ["BodySerialNumber", "CameraSerialNumber", "SerialNumber", "InternalSerialNumber"]
    private static let isoKeys: Set<String> = ["ISOSpeedRatings", "PhotographicSensitivity", "ISOSpeed", "RecommendedExposureIndex", "ISO"]

    private static let linearLUT: [Float] = (0...255).map { byte in
        let u = Float(byte) / 255
        return u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4)
    }

    private static func paint(_ image: CGImage, mid: Float, dark: Float) -> CGImage? {
        let w = image.width
        let h = image.height
        let row = (w * 4 + 63) & ~63
        let bytes = row * h
        guard bytes > 0, bytes < 400_000_000 else { return image }
        guard let src = malloc(bytes), let dst = malloc(bytes) else { return image }
        defer { free(src); free(dst) }
        memset(src, 0, bytes)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let ctx = CGContext(
            data: src, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row, space: space, bitmapInfo: info
        ) else { return image }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = src.assumingMemoryBound(to: UInt8.self)
        if dark > 0.45 { unstick(pixels, w: w, h: h, row: row) }
        let radius = max(1, min(5, Int((max(mid, dark) * 6).rounded())))
        var source = vImage_Buffer(data: src, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: row)
        var blurred = vImage_Buffer(data: dst, height: vImagePixelCount(h), width: vImagePixelCount(w), rowBytes: row)
        let kernel = UInt32(radius * 2 + 1)
        guard vImageBoxConvolve_ARGB8888(&source, &blurred, nil, 0, 0, kernel, kernel, nil, vImage_Flags(kvImageEdgeExtend)) == kvImageNoError else {
            return image
        }
        let soft = dst.assumingMemoryBound(to: UInt8.self)
        let lut = linearLUT
        for y in 0..<h {
            let line = y * row
            for x in 0..<w {
                let o = line + x * 4
                let r = Int(pixels[o + 1])
                let g = Int(pixels[o + 2])
                let b = Int(pixels[o + 3])
                let yLin = 0.25 * lut[r] + 0.5 * lut[g] + 0.25 * lut[b]
                let t = min(1, max(0, (0.18 - yLin) / 0.15))
                let chroma = (mid + (dark - mid) * t) * 0.9
                let luma = chroma * 0.28
                let br = Float(soft[o + 1])
                let bg = Float(soft[o + 2])
                let bb = Float(soft[o + 3])
                let oy = 0.25 * Float(r) + 0.5 * Float(g) + 0.25 * Float(b)
                let by = 0.25 * br + 0.5 * bg + 0.25 * bb
                let outY = oy * (1 - luma) + by * luma
                pixels[o + 1] = byte(outY + (Float(r) - oy) * (1 - chroma) + (br - by) * chroma)
                pixels[o + 2] = byte(outY + (Float(g) - oy) * (1 - chroma) + (bg - by) * chroma)
                pixels[o + 3] = byte(outY + (Float(b) - oy) * (1 - chroma) + (bb - by) * chroma)
            }
        }
        return ctx.makeImage()
    }

    private static func byte(_ v: Float) -> UInt8 {
        UInt8(min(255, max(0, v + 0.5)))
    }

    /// A pixel that stands off a flat neighborhood is a hot or dead photosite. Replace it before the blur so it does not bloom.
    private static func unstick(_ px: UnsafeMutablePointer<UInt8>, w: Int, h: Int, row: Int) {
        guard w > 2, h > 2 else { return }
        let steps = [(-1, 0), (1, 0), (0, -1), (0, 1)]
        for y in 1..<(h - 1) {
            for x in 1..<(w - 1) {
                let i = y * row + x * 4
                var greens: [Int] = []
                greens.reserveCapacity(4)
                for (dy, dx) in steps {
                    greens.append(Int(px[(y + dy) * row + (x + dx) * 4 + 2]))
                }
                greens.sort()
                let spread = greens[3] - greens[0]
                let med = (greens[1] + greens[2]) / 2
                guard abs(Int(px[i + 2]) - med) > 36, spread < 14 else { continue }
                for c in 1...3 {
                    var ch: [Int] = []
                    ch.reserveCapacity(4)
                    for (dy, dx) in steps {
                        ch.append(Int(px[(y + dy) * row + (x + dx) * 4 + c]))
                    }
                    ch.sort()
                    px[i + c] = UInt8((ch[1] + ch[2]) / 2)
                }
            }
        }
    }
}

enum NoiseField {
    static func measure(_ image: CGImage) -> (mr: Float, mg: Float, mb: Float, vr: Float, vg: Float, vb: Float) {
        let edge = max(image.width, image.height)
        let scale = min(1, 640 / CGFloat(max(edge, 1)))
        let w = max(8, Int((CGFloat(image.width) * scale).rounded()))
        let h = max(8, Int((CGFloat(image.height) * scale).rounded()))
        let row = w * 4
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: row, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return (0, 0, 0, 0, 0, 0) }
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = data.assumingMemoryBound(to: UInt8.self)
        let lut = (0...255).map { byte -> Float in
            let u = Float(byte) / 255
            return u <= 0.04045 ? u / 12.92 : pow((u + 0.055) / 1.055, 2.4)
        }
        let x0 = w / 4
        let x1 = max(x0 + 1, w * 3 / 4)
        let y0 = h / 4
        let y1 = max(y0 + 1, h * 3 / 4)
        var n: Float = 0
        var sr: Float = 0, sg: Float = 0, sb: Float = 0
        var qr: Float = 0, qg: Float = 0, qb: Float = 0
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let i = y * row + x * 4
                let r = lut[Int(px[i])]
                let g = lut[Int(px[i + 1])]
                let b = lut[Int(px[i + 2])]
                sr += r; sg += g; sb += b
                qr += r * r; qg += g * g; qb += b * b
                n += 1
                x += 2
            }
            y += 2
        }
        guard n > 0 else { return (0, 0, 0, 0, 0, 0) }
        let mr = sr / n, mg = sg / n, mb = sb / n
        return (mr, mg, mb, max(0, qr / n - mr * mr), max(0, qg / n - mg * mg), max(0, qb / n - mb * mb))
    }

    /// A stand-in frame with the same variance = a × mean + b shape the real bodies are fitted to.
    static func synthetic(iso: Int, shutter: String) -> CGImage {
        let mean: Float
        switch shutter {
        case "1/1000": mean = 0.06
        case "1/4": mean = 0.55
        default: mean = 0.22
        }
        let gain = Float(max(iso, 100)) / 100
        let a = 0.0008 * gain
        let b = 0.000002 * gain * gain
        let w = 320, h = 240
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        guard let ctx, let data = ctx.data else {
            return ctx?.makeImage() ?? blank()
        }
        var rng = SplitMix(state: UInt64(iso) &* 0x9E37 &+ UInt64(bitPattern: Int64(shutter.hashValue)))
        let px = data.assumingMemoryBound(to: UInt8.self)
        let sigma = sqrt(a * mean + b)
        for i in 0..<(w * h) {
            let r = encode(min(1, max(0, mean + rng.gauss() * sigma)))
            let g = encode(min(1, max(0, mean + rng.gauss() * sigma * 0.92)))
            let b = encode(min(1, max(0, mean + rng.gauss() * sigma * 1.08)))
            px[i * 4] = r
            px[i * 4 + 1] = g
            px[i * 4 + 2] = b
            px[i * 4 + 3] = 255
        }
        return ctx.makeImage() ?? blank()
    }

    private static func encode(_ y: Float) -> UInt8 {
        let x = min(1, max(0, y))
        let e = x <= 0.0031308 ? x * 12.92 : 1.055 * pow(x, 1 / 2.4) - 0.055
        return UInt8(min(255, max(0, e * 255 + 0.5)))
    }

    private static func blank() -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        return ctx.makeImage()!
    }

    private struct SplitMix {
        var state: UInt64
        mutating func unit() -> Float {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            z = z ^ (z >> 31)
            return Float(z >> 40) / Float(1 << 24)
        }
        mutating func gauss() -> Float {
            let u = max(1e-6, unit())
            let v = unit()
            return sqrt(-2 * log(u)) * cos(2 * Float.pi * v)
        }
    }
}
