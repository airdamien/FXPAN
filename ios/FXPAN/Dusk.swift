import Accelerate
import CoreGraphics
import Foundation

/// Zero-DCE++ (Li, Guo, Loy, TPAMI 2022). A 10k-parameter net estimates one pixel curve on a 12× downsample, then that curve is applied at full size.
/// Eight passes of x + a·(x² − x) bend the tone that is already there. The weights are the authors' Epoch99 snapshot, used only when this set has Dusk on.
enum Dusk {
    private static let scale = 12
    private static let spec: [(Int, Int)] = [(3, 32), (32, 32), (32, 32), (32, 32), (64, 32), (64, 32), (64, 3)]

    static func lift(_ image: CGImage) -> CGImage {
        let w = image.width
        let h = image.height
        guard w > 1, h > 1 else { return image }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let data = ctx.data else { return image }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let pixels = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var rgb = [UInt8](repeating: 0, count: w * h * 3)
        for i in 0..<(w * h) {
            rgb[i * 3] = pixels[i * 4]
            rgb[i * 3 + 1] = pixels[i * 4 + 1]
            rgb[i * 3 + 2] = pixels[i * 4 + 2]
        }
        let lifted = apply(rgb: rgb, width: w, height: h)
        for i in 0..<(w * h) {
            pixels[i * 4] = lifted[i * 3]
            pixels[i * 4 + 1] = lifted[i * 3 + 1]
            pixels[i * 4 + 2] = lifted[i * 3 + 2]
            pixels[i * 4 + 3] = 255
        }
        return ctx.makeImage() ?? image
    }

    /// Packed RGB in, packed RGB out. The frame is edge-padded to a multiple of 12 so the last columns are lifted too.
    static func apply(rgb: [UInt8], width: Int, height: Int) -> [UInt8] {
        let layers = weights()
        guard layers.count == spec.count, width > 1, height > 1 else { return rgb }
        let padW = ((width + scale - 1) / scale) * scale
        let padH = ((height + scale - 1) / scale) * scale
        let lowW = padW / scale
        let lowH = padH / scale
        let down = downsample(rgb, width, height, lowW, lowH, padW, padH)
        let curve = network(down, lowW, lowH, layers)
        guard curve.count == 3 * lowW * lowH else { return rgb }
        return paint(rgb, width, height, curve, lowW, lowH, padW, padH)
    }

    private struct Layer {
        var cin: Int
        var cout: Int
        var depthW: [Float]
        var depthB: [Float]
        var pointW: [Float]
        var pointB: [Float]
    }

    private static func weights() -> [Layer] {
        let raw = DuskWeights.blob
        let count = raw.count / MemoryLayout<Float>.size
        guard count > 0 else { return [] }
        var floats = [Float](repeating: 0, count: count)
        _ = floats.withUnsafeMutableBytes { raw.copyBytes(to: $0) }
        var cursor = 0
        var layers: [Layer] = []
        for (cin, cout) in spec {
            let n = cin * 9 + cin + cout * cin + cout
            guard cursor + n <= floats.count else { return [] }
            let dw = Array(floats[cursor..<(cursor + cin * 9)])
            cursor += cin * 9
            let db = Array(floats[cursor..<(cursor + cin)])
            cursor += cin
            let pw = Array(floats[cursor..<(cursor + cout * cin)])
            cursor += cout * cin
            let pb = Array(floats[cursor..<(cursor + cout)])
            cursor += cout
            layers.append(Layer(cin: cin, cout: cout, depthW: dw, depthB: db, pointW: pw, pointB: pb))
        }
        return layers
    }

    /// Bilinear, align_corners false, matching the PyTorch resize the net was run with. Samples past the frame repeat the edge.
    private static func downsample(_ rgb: [UInt8], _ w: Int, _ h: Int, _ lowW: Int, _ lowH: Int, _ padW: Int, _ padH: Int) -> [Float] {
        var out = [Float](repeating: 0, count: 3 * lowW * lowH)
        let scaleX = Float(padW) / Float(lowW)
        let scaleY = Float(padH) / Float(lowH)
        for y in 0..<lowH {
            let (y0, y1, ty) = srcIndex(Float(y), scaleY, h)
            for x in 0..<lowW {
                let (x0, x1, tx) = srcIndex(Float(x), scaleX, w)
                for c in 0..<3 {
                    let p00 = Float(rgb[(y0 * w + x0) * 3 + c])
                    let p01 = Float(rgb[(y0 * w + x1) * 3 + c])
                    let p10 = Float(rgb[(y1 * w + x0) * 3 + c])
                    let p11 = Float(rgb[(y1 * w + x1) * 3 + c])
                    let top = p00 * (1 - tx) + p01 * tx
                    let bot = p10 * (1 - tx) + p11 * tx
                    out[(c * lowH + y) * lowW + x] = (top * (1 - ty) + bot * ty) / 255
                }
            }
        }
        return out
    }

    private static func srcIndex(_ dst: Float, _ scale: Float, _ limit: Int) -> (Int, Int, Float) {
        var src = scale * (dst + 0.5) - 0.5
        if src < 0 { src = 0 }
        let i0 = min(Int(src), limit - 1)
        let i1 = min(i0 + 1, limit - 1)
        let t = i0 == limit - 1 ? Float(0) : src - Float(i0)
        return (i0, i1, t)
    }

    private static func network(_ input: [Float], _ w: Int, _ h: Int, _ layers: [Layer]) -> [Float] {
        // The last three layers each see the current map stacked with an earlier one, the same skip the published net uses.
        let x1 = relu(conv(input, w, h, layers[0]))
        let x2 = relu(conv(x1, w, h, layers[1]))
        let x3 = relu(conv(x2, w, h, layers[2]))
        let x4 = relu(conv(x3, w, h, layers[3]))
        let x5 = relu(conv(cat(x3, x4), w, h, layers[4]))
        let x6 = relu(conv(cat(x2, x5), w, h, layers[5]))
        return tanh(conv(cat(x1, x6), w, h, layers[6]))
    }

    private static func cat(_ a: [Float], _ b: [Float]) -> [Float] {
        a + b
    }

    private static func relu(_ x: [Float]) -> [Float] {
        var zero: Float = 0
        var out = [Float](repeating: 0, count: x.count)
        vDSP_vthres(x, 1, &zero, &out, 1, vDSP_Length(x.count))
        return out
    }

    private static func tanh(_ x: [Float]) -> [Float] {
        var n = Int32(x.count)
        var out = [Float](repeating: 0, count: x.count)
        vvtanhf(&out, x, &n)
        return out
    }

    private static func conv(_ input: [Float], _ w: Int, _ h: Int, _ layer: Layer) -> [Float] {
        let pixels = w * h
        let mid = depthwise(input, w, h, layer)
        var out = [Float](repeating: 0, count: layer.cout * pixels)
        let cout = layer.cout
        let cin = layer.cin
        mid.withUnsafeBufferPointer { xPtr in
            layer.pointW.withUnsafeBufferPointer { wPtr in
                out.withUnsafeMutableBufferPointer { yPtr in
                    guard let x = xPtr.baseAddress, let wp = wPtr.baseAddress, let y = yPtr.baseAddress else { return }
                    cblas_sgemm(
                        CblasRowMajor, CblasNoTrans, CblasNoTrans,
                        Int32(cout), Int32(pixels), Int32(cin),
                        1, wp, Int32(cin), x, Int32(pixels),
                        0, y, Int32(pixels)
                    )
                    for c in 0..<cout {
                        var bias = layer.pointB[c]
                        vDSP_vsadd(y + c * pixels, 1, &bias, y + c * pixels, 1, vDSP_Length(pixels))
                    }
                }
            }
        }
        return out
    }

    private static func depthwise(_ input: [Float], _ w: Int, _ h: Int, _ layer: Layer) -> [Float] {
        let pixels = w * h
        var mid = [Float](repeating: 0, count: layer.cin * pixels)
        input.withUnsafeBufferPointer { srcBuf in
            mid.withUnsafeMutableBufferPointer { dstBuf in
                layer.depthW.withUnsafeBufferPointer { kBuf in
                    guard let src = srcBuf.baseAddress, let dst = dstBuf.baseAddress, let kern = kBuf.baseAddress else { return }
                    for c in 0..<layer.cin {
                        let s = src + c * pixels
                        let d = dst + c * pixels
                        let k = kern + c * 9
                        let b = layer.depthB[c]
                        if h > 2, w > 2 {
                            for y in 1..<(h - 1) {
                                for x in 1..<(w - 1) {
                                    let i = y * w + x
                                    d[i] = b
                                        + s[i - w - 1] * k[0] + s[i - w] * k[1] + s[i - w + 1] * k[2]
                                        + s[i - 1] * k[3] + s[i] * k[4] + s[i + 1] * k[5]
                                        + s[i + w - 1] * k[6] + s[i + w] * k[7] + s[i + w + 1] * k[8]
                                }
                            }
                        }
                        for y in 0..<h {
                            let edge = y == 0 || y == h - 1 || h <= 2 || w <= 2
                            let xs = edge ? Array(0..<w) : [0, w - 1]
                            for x in xs {
                                var acc = b
                                for ky in 0..<3 {
                                    let iy = y + ky - 1
                                    if iy < 0 || iy >= h { continue }
                                    for kx in 0..<3 {
                                        let ix = x + kx - 1
                                        if ix < 0 || ix >= w { continue }
                                        acc += s[iy * w + ix] * k[ky * 3 + kx]
                                    }
                                }
                                d[y * w + x] = acc
                            }
                        }
                    }
                }
            }
        }
        return mid
    }

    private static func paint(_ rgb: [UInt8], _ w: Int, _ h: Int, _ curve: [Float], _ lowW: Int, _ lowH: Int, _ padW: Int, _ padH: Int) -> [UInt8] {
        var out = rgb
        let scaleX = Float(lowW) / Float(padW)
        let scaleY = Float(lowH) / Float(padH)
        var row0 = [[Float]](repeating: [Float](repeating: 0, count: padW), count: 3)
        var row1 = [[Float]](repeating: [Float](repeating: 0, count: padW), count: 3)
        curve.withUnsafeBufferPointer { curveBuf in
            guard let base = curveBuf.baseAddress else { return }
            for y in 0..<h {
                let (y0, y1, ty) = srcIndex(Float(y), scaleY, lowH)
                for c in 0..<3 {
                    stretch(base + (c * lowH + y0) * lowW, lowW, &row0[c], padW, scaleX)
                    stretch(base + (c * lowH + y1) * lowW, lowW, &row1[c], padW, scaleX)
                }
                for x in 0..<w {
                    let i = (y * w + x) * 3
                    for c in 0..<3 {
                        let a = row0[c][x] * (1 - ty) + row1[c][x] * ty
                        var v = Float(rgb[i + c]) / 255
                        for _ in 0..<8 {
                            v += a * (v * v - v)
                        }
                        out[i + c] = UInt8(min(255, max(0, (v * 255).rounded())))
                    }
                }
            }
        }
        return out
    }

    private static func stretch(_ src: UnsafePointer<Float>, _ srcW: Int, _ dst: inout [Float], _ dstW: Int, _ scale: Float) {
        for x in 0..<dstW {
            let (x0, x1, tx) = srcIndex(Float(x), scale, srcW)
            dst[x] = src[x0] * (1 - tx) + src[x1] * tx
        }
    }
}
