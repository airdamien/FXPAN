import CoreGraphics
import CoreImage
import CoreML
import Foundation
import Vision

/// realesr-general-x4v3, tiled. Subject tiles go through the network. The rest of the frame is scaled to the same size, and the overlap is blended so the tiles do not show a seam.
enum SuperRes {
    static let tile = 256
    static let modelScale = 4
    static let overlap = 32

    static func image(_ source: CGImage, note: ((String) -> Void)? = nil) throws -> (CGImage, Int) {
        let src = Stitcher.bitmap(source)
        let outScale = outputScale(width: src.w, height: src.h)
        guard outScale == 2 || outScale == 4 else {
            throw PTPError.message("This frame is too large to upscale")
        }
        let outW = src.w * outScale
        let outH = src.h * outScale
        var canvas = [UInt8](repeating: 0, count: outW * outH * 4)
        let mask = subjectMask(source)
        let net = try Network.load()
        let step = tile - overlap
        let xs = origins(src.w, step: step)
        let ys = origins(src.h, step: step)
        let total = xs.count * ys.count
        var done = 0
        var neural = 0
        for oy in ys {
            try StitchGate.check { Task.isCancelled }
            for ox in xs {
                let useNet = coversSubject(mask, ox: ox, oy: oy, srcW: src.w, srcH: src.h)
                var patch: Patch?
                var usedNet = false
                autoreleasepool {
                    if useNet, let made = netPatch(net, src: src, ox: ox, oy: oy, outScale: outScale) {
                        patch = made
                        usedNet = true
                    } else {
                        patch = plainPatch(src: src, ox: ox, oy: oy, outScale: outScale)
                    }
                }
                if usedNet { neural += 1 }
                if let patch {
                    blend(&canvas, outW: outW, outH: outH, patch: patch, ox: ox * outScale, oy: oy * outScale, outScale: outScale)
                }
                done += 1
                if done == 1 || done == total || done % 8 == 0 {
                    note?("Upscaling \(done) of \(total)")
                }
            }
        }
        guard neural > 0 else { throw PTPError.message("Could not run the upscaler") }
        return (Stitcher.Bitmap(w: outW, h: outH, px: canvas).image(), outScale)
    }

    /// 4× when the result fits in about 1.2 GB. A full panorama steps down to 2×, which is still the 4× model averaged in pairs.
    private static func outputScale(width: Int, height: Int) -> Int {
        let pixels = Double(width) * Double(height)
        if pixels * 16 * 4 <= 1_200_000_000 { return 4 }
        if pixels * 4 * 4 <= 1_400_000_000 { return 2 }
        return 0
    }

    private static func origins(_ length: Int, step: Int) -> [Int] {
        if length <= tile { return [0] }
        var values: [Int] = []
        var cursor = 0
        while cursor + tile < length {
            values.append(cursor)
            cursor += step
        }
        let last = max(0, length - tile)
        if values.last != last { values.append(last) }
        return values
    }

    private struct Mask {
        var w: Int
        var h: Int
        var px: [UInt8]
    }

    private static func subjectMask(_ image: CGImage) -> Mask? {
        let maxSide = 960
        let scale = min(1, Double(maxSide) / Double(max(image.width, image.height)))
        let w = max(1, Int((Double(image.width) * scale).rounded()))
        let h = max(1, Int((Double(image.height) * scale).rounded()))
        let small = Stitcher.sized(image, to: w, height: h)
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: small, options: [:])
        guard (try? handler.perform([request])) != nil,
              let obs = request.results?.first as? VNInstanceMaskObservation,
              obs.allInstances.count > 0,
              let buffer = try? obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler) else {
            return nil
        }
        let ci = CIImage(cvPixelBuffer: buffer)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cg = ctx.createCGImage(ci, from: ci.extent) else { return nil }
        let gray = Stitcher.gray(cg, width: cg.width)
        return Mask(w: gray.w, h: gray.h, px: gray.pix)
    }

    /// A tile counts when the subject touches it, plus one tile of padding so the edge of a person is not left on the plain scale.
    private static func coversSubject(_ mask: Mask?, ox: Int, oy: Int, srcW: Int, srcH: Int) -> Bool {
        guard let mask else { return true }
        let pad = tile
        let x0 = max(0, ox - pad)
        let y0 = max(0, oy - pad)
        let x1 = min(srcW, ox + tile + pad)
        let y1 = min(srcH, oy + tile + pad)
        var hit = 0
        var seen = 0
        let sx = Double(mask.w) / Double(srcW)
        let sy = Double(mask.h) / Double(srcH)
        let mx0 = Int(Double(x0) * sx)
        let my0 = Int(Double(y0) * sy)
        let mx1 = min(mask.w, max(mx0 + 1, Int(Double(x1) * sx)))
        let my1 = min(mask.h, max(my0 + 1, Int(Double(y1) * sy)))
        for y in stride(from: my0, to: my1, by: 2) {
            for x in stride(from: mx0, to: mx1, by: 2) {
                seen += 1
                if mask.px[y * mask.w + x] > 16 { hit += 1 }
            }
        }
        return seen > 0 && hit * 20 >= seen
    }

    private struct Patch {
        var w: Int
        var h: Int
        var px: [UInt8]
    }

    private static func netPatch(_ net: Network, src: Stitcher.Bitmap, ox: Int, oy: Int, outScale: Int) -> Patch? {
        guard let out = net.predict(src, ox: ox, oy: oy) else { return nil }
        let validW = min(tile, src.w - ox) * outScale
        let validH = min(tile, src.h - oy) * outScale
        let factor = modelScale / outScale
        var px = [UInt8](repeating: 0, count: validW * validH * 4)
        for y in 0..<validH {
            for x in 0..<validW {
                var rgb = (0, 0, 0)
                if factor == 1 {
                    rgb = out.sample(x, y)
                } else {
                    var sum = (0, 0, 0)
                    let x0 = x * factor
                    let y0 = y * factor
                    for dy in 0..<factor {
                        for dx in 0..<factor {
                            let s = out.sample(x0 + dx, y0 + dy)
                            sum.0 += s.0
                            sum.1 += s.1
                            sum.2 += s.2
                        }
                    }
                    let n = factor * factor
                    rgb = (sum.0 / n, sum.1 / n, sum.2 / n)
                }
                let i = (y * validW + x) * 4
                px[i] = UInt8(rgb.0)
                px[i + 1] = UInt8(rgb.1)
                px[i + 2] = UInt8(rgb.2)
                px[i + 3] = 255
            }
        }
        return Patch(w: validW, h: validH, px: px)
    }

    private static func plainPatch(src: Stitcher.Bitmap, ox: Int, oy: Int, outScale: Int) -> Patch? {
        let validW = min(tile, src.w - ox)
        let validH = min(tile, src.h - oy)
        let outW = validW * outScale
        let outH = validH * outScale
        var tilePx = [UInt8](repeating: 0, count: validW * validH * 4)
        for y in 0..<validH {
            let s = ((oy + y) * src.w + ox) * 4
            let d = y * validW * 4
            tilePx.replaceSubrange(d..<(d + validW * 4), with: src.px[s..<(s + validW * 4)])
        }
        let scaled = Stitcher.sized(Stitcher.Bitmap(w: validW, h: validH, px: tilePx).image(), to: outW, height: outH)
        let bitmap = Stitcher.bitmap(scaled)
        return Patch(w: bitmap.w, h: bitmap.h, px: bitmap.px)
    }

    private static func blend(_ canvas: inout [UInt8], outW: Int, outH: Int, patch: Patch, ox: Int, oy: Int, outScale: Int) {
        let feather = overlap * outScale
        for y in 0..<patch.h {
            let dy = oy + y
            if dy < 0 || dy >= outH { continue }
            for x in 0..<patch.w {
                let dx = ox + x
                if dx < 0 || dx >= outW { continue }
                var weight = Float(1)
                if ox > 0 && x < feather { weight = min(weight, Float(x) / Float(feather)) }
                if oy > 0 && y < feather { weight = min(weight, Float(y) / Float(feather)) }
                let si = (y * patch.w + x) * 4
                let di = (dy * outW + dx) * 4
                if weight > 0.999 || canvas[di + 3] == 0 {
                    canvas[di] = patch.px[si]
                    canvas[di + 1] = patch.px[si + 1]
                    canvas[di + 2] = patch.px[si + 2]
                    canvas[di + 3] = 255
                } else {
                    let keep = 1 - weight
                    for c in 0..<3 {
                        let mixed = Float(canvas[di + c]) * keep + Float(patch.px[si + c]) * weight
                        canvas[di + c] = UInt8(min(255, max(0, mixed.rounded())))
                    }
                    canvas[di + 3] = 255
                }
            }
        }
    }

    private struct Plane {
        var data: [Float]
        func sample(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let side = tile * modelScale
            let xx = min(side - 1, max(0, x))
            let yy = min(side - 1, max(0, y))
            func channel(_ c: Int) -> Int {
                let v = data[c * side * side + yy * side + xx] * 255
                return Int(min(255, max(0, v.rounded())))
            }
            return (channel(0), channel(1), channel(2))
        }
    }

    private final class Network {
        let model: MLModel
        let input: MLMultiArray
        let strides: [Int]

        static func load() throws -> Network {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            let bundle = Bundle.main
            if let compiled = bundle.url(forResource: "RealESRGAN-x4v3", withExtension: "mlmodelc")
                ?? bundle.url(forResource: "RealESRGAN-x4v3", withExtension: "mlmodelc", subdirectory: "Models") {
                return try Network(model: MLModel(contentsOf: compiled, configuration: config))
            }
            guard let package = bundle.url(forResource: "RealESRGAN-x4v3", withExtension: "mlpackage")
                ?? bundle.url(forResource: "RealESRGAN-x4v3", withExtension: "mlpackage", subdirectory: "Models") else {
                throw PTPError.message("The upscaler model is missing")
            }
            let compiled = try MLModel.compileModel(at: package)
            return try Network(model: MLModel(contentsOf: compiled, configuration: config))
        }

        init(model: MLModel) throws {
            self.model = model
            input = try MLMultiArray(shape: [1, 3, NSNumber(value: tile), NSNumber(value: tile)], dataType: .float16)
            strides = input.strides.map(\.intValue)
        }

        func predict(_ src: Stitcher.Bitmap, ox: Int, oy: Int) -> Plane? {
            let ptr = input.dataPointer.bindMemory(to: Float16.self, capacity: 3 * tile * tile)
            let channels = strides.count > 1 ? strides[1] : tile * tile
            let rows = strides.count > 2 ? strides[2] : tile
            for y in 0..<tile {
                let sy = min(src.h - 1, max(0, oy + y))
                for x in 0..<tile {
                    let sx = min(src.w - 1, max(0, ox + x))
                    let p = (sy * src.w + sx) * 4
                    let offset = y * rows + x
                    ptr[offset] = Float16(src.px[p]) / 255
                    ptr[channels + offset] = Float16(src.px[p + 1]) / 255
                    ptr[channels * 2 + offset] = Float16(src.px[p + 2]) / 255
                }
            }
            guard let features = try? MLDictionaryFeatureProvider(dictionary: ["input": input]),
                  let result = try? model.prediction(from: features),
                  let array = result.featureValue(for: "output")?.multiArrayValue else { return nil }
            let side = tile * modelScale
            var data = [Float](repeating: 0, count: 3 * side * side)
            let outStrides = array.strides.map(\.intValue)
            let base = array.dataPointer.bindMemory(to: Float16.self, capacity: 3 * side * side)
            let cStride = outStrides.count > 1 ? outStrides[1] : side * side
            let rStride = outStrides.count > 2 ? outStrides[2] : side
            for c in 0..<3 {
                for y in 0..<side {
                    for x in 0..<side {
                        data[c * side * side + y * side + x] = Float(base[c * cStride + y * rStride + x])
                    }
                }
            }
            return Plane(data: data)
        }
    }
}
