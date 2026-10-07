import Foundation
import Metal

/// SIFT on the overlap strip. The CPU path stays when the device refuses a buffer or the pyramid overflows.
enum SiftGPU {
    struct Key {
        var x: Float
        var y: Float
        var sigma: Float
        var angle: Float
        var response: Float
        var d: [Float]
    }

    struct Rank {
        var index: Int?
        var best: Float
        var second: Float
    }

    static func find(pixels: [Float], w: Int, h: Int) -> [Key]? {
        guard w >= 16, h >= 16, pixels.count >= w * h, let gpu = GPU.shared else { return nil }
        let started = CFAbsoluteTimeGetCurrent()
        guard let keys = gpu.find(pixels: pixels, w: w, h: h) else { return nil }
        print(String(format: "FXPAN sift metal %dx%d keys=%d %.2fs", w, h, keys.count, CFAbsoluteTimeGetCurrent() - started))
        return keys
    }

    /// Best and second-best descriptor distance for each key on the right. Nil sends the match back to the CPU.
    static func rank(leftY: [Float], leftD: [Float], rightY: [Float], rightD: [Float], gate: Float) -> [Rank]? {
        guard let gpu = GPU.shared else { return nil }
        let nL = leftY.count
        let nR = rightY.count
        guard nL > 0, nR > 0, leftD.count == nL * 128, rightD.count == nR * 128 else { return nil }
        return gpu.rank(leftY: leftY, leftD: leftD, rightY: rightY, rightD: rightD, gate: gate)
    }

    private struct Cand {
        var x: Float
        var y: Float
        var sigma: Float
        var response: Float
        var ox: Float
        var oy: Float
        var osigma: Float
        var octave: UInt32
        var layer: UInt32
        var pad: UInt32
    }

    private struct OrientKey {
        var x: Float
        var y: Float
        var sigma: Float
        var angle: Float
        var response: Float
        var ox: Float
        var oy: Float
        var osigma: Float
        var octave: UInt32
        var layer: UInt32
        var pad0: UInt32
        var pad1: UInt32
    }

    private struct DescIn {
        var ox: Float
        var oy: Float
        var osigma: Float
        var angle: Float
        var index: UInt32
        var pad0: UInt32
        var pad1: UInt32
        var pad2: UInt32
    }

    private struct Extrema {
        var prelim: Float
        var scale: Float
        var sigma: Float
        var osigma: Float
        var octave: UInt32
        var layer: UInt32
        var cap: UInt32
        var pad: UInt32
    }

    private struct MatchIn {
        var nL: UInt32
        var nR: UInt32
        var gate: Float
        var pad: UInt32
    }

    private struct Dist {
        var best: Float
        var second: Float
    }

    private final class GPU {
        static let shared: GPU? = GPU()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let blurH: MTLComputePipelineState
        let blurV: MTLComputePipelineState
        let down2: MTLComputePipelineState
        let dog: MTLComputePipelineState
        let extrema: MTLComputePipelineState
        let orient: MTLComputePipelineState
        let describe: MTLComputePipelineState
        let match: MTLComputePipelineState
        let cap = 100_000
        let keep = 800

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let library: MTLLibrary?
            if let path = ProcessInfo.processInfo.environment["FXPAN_SIFT_METALLIB"] {
                library = try? device.makeLibrary(URL: URL(fileURLWithPath: path))
            } else {
                library = device.makeDefaultLibrary()
            }
            guard let library else { return nil }
            func pipe(_ name: String) -> MTLComputePipelineState? {
                guard let fn = library.makeFunction(name: name) else {
                    print("FXPAN sift metal missing \(name)")
                    return nil
                }
                do { return try device.makeComputePipelineState(function: fn) }
                catch {
                    print("FXPAN sift metal \(name) \(error.localizedDescription)")
                    return nil
                }
            }
            guard let blurH = pipe("fxpanBlurH"), let blurV = pipe("fxpanBlurV"), let down2 = pipe("fxpanDown2"),
                  let dog = pipe("fxpanDog"), let extrema = pipe("fxpanExtrema"), let orient = pipe("fxpanOrient"),
                  let describe = pipe("fxpanDescribe"), let match = pipe("fxpanMatch") else { return nil }
            self.device = device
            self.queue = queue
            self.blurH = blurH
            self.blurV = blurV
            self.down2 = down2
            self.dog = dog
            self.extrema = extrema
            self.orient = orient
            self.describe = describe
            self.match = match
        }

        func find(pixels: [Float], w: Int, h: Int) -> [Key]? {
            let layers = 3
            let sigma0 = 1.6
            let k = pow(2.0, 1.0 / Double(layers))
            var blurSteps = [Double](repeating: 0, count: layers + 3)
            for i in 1..<(layers + 3) {
                let prev = pow(k, Double(i - 1)) * sigma0
                let total = prev * k
                blurSteps[i] = (total * total - prev * prev).squareRoot()
            }
            guard let cmd = queue.makeCommandBuffer() else { return nil }
            guard let source = texture(w: w, h: h, upload: pixels) else { return nil }
            let firstSigma = (sigma0 * sigma0 - 0.25).squareRoot()
            var kept: [MTLTexture] = [source]
            guard let base = blur(source, sigma: firstSigma, cmd: cmd, hold: &kept) else { return nil }
            var gauss: [[MTLTexture]] = []
            var current = base
            let octaves = max(1, min(5, Int(log2(Double(min(w, h)))) - 3))
            let counter = device.makeBuffer(length: MemoryLayout<UInt32>.stride, options: .storageModeShared)
            let candBytes = cap * MemoryLayout<Cand>.stride
            guard let counter, candBytes <= device.maxBufferLength, let candBuf = device.makeBuffer(length: candBytes, options: .storageModeShared) else { return nil }
            counter.contents().storeBytes(of: UInt32(0), as: UInt32.self)
            for oct in 0..<octaves {
                var level: [MTLTexture] = [current]
                for i in 1..<(layers + 3) {
                    guard let next = blur(level[i - 1], sigma: blurSteps[i], cmd: cmd, hold: &kept) else { return nil }
                    level.append(next)
                }
                gauss.append(level)
                var dogs: [MTLTexture] = []
                for i in 0..<(level.count - 1) {
                    guard let d = dog(level[i], level[i + 1], cmd: cmd, hold: &kept) else { return nil }
                    dogs.append(d)
                }
                let scale = Float(1 << oct)
                for li in 1..<(dogs.count - 1) {
                    var job = Extrema(
                        prelim: Float(0.5 * 0.02 / Double(layers)),
                        scale: scale,
                        sigma: Float(sigma0 * pow(k, Double(li)) * Double(scale)),
                        osigma: Float(sigma0 * pow(k, Double(li))),
                        octave: UInt32(oct),
                        layer: UInt32(li),
                        cap: UInt32(cap),
                        pad: 0
                    )
                    guard let enc = cmd.makeComputeCommandEncoder() else { return nil }
                    enc.setComputePipelineState(extrema)
                    enc.setTexture(dogs[li - 1], index: 0)
                    enc.setTexture(dogs[li], index: 1)
                    enc.setTexture(dogs[li + 1], index: 2)
                    enc.setBuffer(candBuf, offset: 0, index: 0)
                    enc.setBuffer(counter, offset: 0, index: 1)
                    enc.setBytes(&job, length: MemoryLayout<Extrema>.stride, index: 2)
                    dispatch(enc, extrema, dogs[li].width, dogs[li].height)
                    enc.endEncoding()
                }
                guard oct + 1 < octaves else { break }
                let src = level[layers]
                let nw = src.width / 2
                let nh = src.height / 2
                if nw < 16 || nh < 16 { break }
                guard let down = texture(w: nw, h: nh, upload: nil) else { return nil }
                kept.append(down)
                guard let enc = cmd.makeComputeCommandEncoder() else { return nil }
                enc.setComputePipelineState(down2)
                enc.setTexture(src, index: 0)
                enc.setTexture(down, index: 1)
                dispatch(enc, down2, nw, nh)
                enc.endEncoding()
                current = down
            }
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else {
                print("FXPAN sift metal pyramid \(cmd.status.rawValue)")
                return nil
            }
            let found = Int(counter.contents().load(as: UInt32.self))
            if found > cap {
                print("FXPAN sift metal overflow \(found)")
                return nil
            }
            if found == 0 { return [] }
            let raw = candBuf.contents().bindMemory(to: Cand.self, capacity: found)
            var cands = Array(UnsafeBufferPointer(start: raw, count: found))
            cands.sort { $0.response > $1.response }
            if cands.count > keep { cands.removeLast(cands.count - keep) }
            guard let oriented = orient(cands, gauss: gauss) else { return nil }
            return describe(oriented, gauss: gauss)
        }

        func rank(leftY: [Float], leftD: [Float], rightY: [Float], rightD: [Float], gate: Float) -> [Rank]? {
            let nL = leftY.count
            let nR = rightY.count
            guard let leftDesc = buffer(leftD), let leftYs = buffer(leftY),
                  let rightDesc = buffer(rightD), let rightYs = buffer(rightY),
                  let bestIndex = device.makeBuffer(length: nR * MemoryLayout<UInt32>.stride, options: .storageModeShared),
                  let bestDist = device.makeBuffer(length: nR * MemoryLayout<Dist>.stride, options: .storageModeShared),
                  let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return nil }
            var job = MatchIn(nL: UInt32(nL), nR: UInt32(nR), gate: gate, pad: 0)
            enc.setComputePipelineState(match)
            enc.setBuffer(leftDesc, offset: 0, index: 0)
            enc.setBuffer(leftYs, offset: 0, index: 1)
            enc.setBuffer(rightDesc, offset: 0, index: 2)
            enc.setBuffer(rightYs, offset: 0, index: 3)
            enc.setBuffer(bestIndex, offset: 0, index: 4)
            enc.setBuffer(bestDist, offset: 0, index: 5)
            enc.setBytes(&job, length: MemoryLayout<MatchIn>.stride, index: 6)
            dispatch(enc, match, nR, 1)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { return nil }
            let who = bestIndex.contents().bindMemory(to: UInt32.self, capacity: nR)
            let dist = bestDist.contents().bindMemory(to: Dist.self, capacity: nR)
            var out: [Rank] = []
            out.reserveCapacity(nR)
            for i in 0..<nR {
                let id = who[i]
                let index: Int? = id == 0xffff_ffff ? nil : Int(id)
                out.append(Rank(index: index, best: dist[i].best, second: dist[i].second))
            }
            return out
        }

        private func orient(_ cands: [Cand], gauss: [[MTLTexture]]) -> [OrientKey]? {
            let groups = Dictionary(grouping: cands.indices) { cands[$0].octave * 16 + cands[$0].layer }
            var oriented: [OrientKey] = []
            oriented.reserveCapacity(cands.count)
            for (_, idxs) in groups {
                let group = idxs.map { cands[$0] }
                guard let oct = group.first.flatMap({ Int($0.octave) }), let layer = group.first.flatMap({ Int($0.layer) }),
                      oct < gauss.count, layer < gauss[oct].count else { return nil }
                let n = group.count
                guard let input = buffer(group),
                      let output = device.makeBuffer(length: n * 4 * MemoryLayout<OrientKey>.stride, options: .storageModeShared),
                      let counts = device.makeBuffer(length: n * MemoryLayout<UInt32>.stride, options: .storageModeShared),
                      let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return nil }
                var count = UInt32(n)
                enc.setComputePipelineState(orient)
                enc.setTexture(gauss[oct][layer], index: 0)
                enc.setBuffer(input, offset: 0, index: 0)
                enc.setBuffer(output, offset: 0, index: 1)
                enc.setBuffer(counts, offset: 0, index: 2)
                enc.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 3)
                dispatch(enc, orient, n, 1)
                enc.endEncoding()
                cmd.commit()
                cmd.waitUntilCompleted()
                guard cmd.status == .completed else { return nil }
                let keys = output.contents().bindMemory(to: OrientKey.self, capacity: n * 4)
                let wrote = counts.contents().bindMemory(to: UInt32.self, capacity: n)
                for i in 0..<n {
                    let m = min(4, Int(wrote[i]))
                    for j in 0..<m { oriented.append(keys[i * 4 + j]) }
                }
            }
            return oriented
        }

        private func describe(_ keys: [OrientKey], gauss: [[MTLTexture]]) -> [Key]? {
            guard !keys.isEmpty else { return [] }
            let groups = Dictionary(grouping: keys.indices) { keys[$0].octave * 16 + keys[$0].layer }
            var desc = [Float](repeating: 0, count: keys.count * 128)
            var ok = [UInt32](repeating: 0, count: keys.count)
            guard let descBuf = buffer(desc), let okBuf = device.makeBuffer(length: keys.count * MemoryLayout<UInt32>.stride, options: .storageModeShared) else { return nil }
            memset(okBuf.contents(), 0, keys.count * MemoryLayout<UInt32>.stride)
            guard let cmd = queue.makeCommandBuffer() else { return nil }
            var held: [MTLBuffer] = []
            for (_, idxs) in groups {
                let inputs: [DescIn] = idxs.map { i in
                    let s = keys[i]
                    return DescIn(ox: s.ox, oy: s.oy, osigma: s.osigma, angle: s.angle, index: UInt32(i), pad0: 0, pad1: 0, pad2: 0)
                }
                let oct = Int(keys[idxs[0]].octave)
                let layer = Int(keys[idxs[0]].layer)
                guard oct < gauss.count, layer < gauss[oct].count,
                      let input = buffer(inputs), let enc = cmd.makeComputeCommandEncoder() else { return nil }
                held.append(input)
                var count = UInt32(inputs.count)
                enc.setComputePipelineState(describe)
                enc.setTexture(gauss[oct][layer], index: 0)
                enc.setBuffer(input, offset: 0, index: 0)
                enc.setBuffer(descBuf, offset: 0, index: 1)
                enc.setBuffer(okBuf, offset: 0, index: 2)
                enc.setBytes(&count, length: MemoryLayout<UInt32>.stride, index: 3)
                dispatch(enc, describe, inputs.count, 1)
                enc.endEncoding()
            }
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { return nil }
            _ = held
            let descBytes = desc.count * MemoryLayout<Float>.stride
            let okBytes = ok.count * MemoryLayout<UInt32>.stride
            desc.withUnsafeMutableBytes { raw in
                raw.copyMemory(from: UnsafeRawBufferPointer(start: descBuf.contents(), count: descBytes))
            }
            ok.withUnsafeMutableBytes { raw in
                raw.copyMemory(from: UnsafeRawBufferPointer(start: okBuf.contents(), count: okBytes))
            }
            var out: [Key] = []
            out.reserveCapacity(keys.count)
            for i in keys.indices where ok[i] == 1 {
                let s = keys[i]
                let d = Array(desc[(i * 128)..<((i + 1) * 128)])
                out.append(Key(x: s.x, y: s.y, sigma: s.sigma, angle: s.angle, response: s.response, d: d))
            }
            return out
        }

        private func blur(_ src: MTLTexture, sigma: Double, cmd: MTLCommandBuffer, hold: inout [MTLTexture]) -> MTLTexture? {
            guard let dst = texture(w: src.width, h: src.height, upload: nil),
                  let temp = texture(w: src.width, h: src.height, upload: nil) else { return nil }
            hold.append(dst)
            hold.append(temp)
            let weights = Self.kernel(sigma: sigma)
            var radius = UInt32((weights.count - 1) / 2)
            guard let encH = cmd.makeComputeCommandEncoder() else { return nil }
            encH.setComputePipelineState(blurH)
            encH.setTexture(src, index: 0)
            encH.setTexture(temp, index: 1)
            weights.withUnsafeBytes { raw in
                if let base = raw.baseAddress { encH.setBytes(base, length: weights.count * MemoryLayout<Float>.stride, index: 0) }
            }
            encH.setBytes(&radius, length: MemoryLayout<UInt32>.stride, index: 1)
            dispatch(encH, blurH, src.width, src.height)
            encH.endEncoding()
            guard let encV = cmd.makeComputeCommandEncoder() else { return nil }
            encV.setComputePipelineState(blurV)
            encV.setTexture(temp, index: 0)
            encV.setTexture(dst, index: 1)
            weights.withUnsafeBytes { raw in
                if let base = raw.baseAddress { encV.setBytes(base, length: weights.count * MemoryLayout<Float>.stride, index: 0) }
            }
            encV.setBytes(&radius, length: MemoryLayout<UInt32>.stride, index: 1)
            dispatch(encV, blurV, src.width, src.height)
            encV.endEncoding()
            return dst
        }

        private func dog(_ a: MTLTexture, _ b: MTLTexture, cmd: MTLCommandBuffer, hold: inout [MTLTexture]) -> MTLTexture? {
            guard let dst = texture(w: a.width, h: a.height, upload: nil), let enc = cmd.makeComputeCommandEncoder() else { return nil }
            hold.append(dst)
            enc.setComputePipelineState(dog)
            enc.setTexture(a, index: 0)
            enc.setTexture(b, index: 1)
            enc.setTexture(dst, index: 2)
            dispatch(enc, dog, a.width, a.height)
            enc.endEncoding()
            return dst
        }

        private func texture(w: Int, h: Int, upload: [Float]?) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            desc.allowGPUOptimizedContents = false
            guard w > 0, h > 0, let tex = device.makeTexture(descriptor: desc) else { return nil }
            if let upload {
                upload.withUnsafeBytes { raw in
                    guard let base = raw.baseAddress else { return }
                    tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * MemoryLayout<Float>.stride)
                }
            }
            return tex
        }

        private func buffer<T>(_ values: [T]) -> MTLBuffer? {
            let bytes = values.count * MemoryLayout<T>.stride
            guard bytes > 0, bytes <= device.maxBufferLength else { return nil }
            return values.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: bytes, options: .storageModeShared)
            }
        }

        private func dispatch(_ enc: MTLComputeCommandEncoder, _ pipe: MTLComputePipelineState, _ w: Int, _ h: Int) {
            let tw = pipe.threadExecutionWidth
            let th = max(1, pipe.maxTotalThreadsPerThreadgroup / tw)
            let threads = MTLSize(width: tw, height: h == 1 ? 1 : th, depth: 1)
            enc.dispatchThreads(MTLSize(width: w, height: h, depth: 1), threadsPerThreadgroup: threads)
        }

        private static func kernel(sigma: Double) -> [Float] {
            let radius = max(1, Int((3 * sigma).rounded()))
            var kernel = [Float](repeating: 0, count: radius * 2 + 1)
            var sum = 0.0
            for i in -radius...radius {
                let v = exp(-0.5 * Double(i * i) / (sigma * sigma))
                kernel[i + radius] = Float(v)
                sum += v
            }
            for i in 0..<kernel.count { kernel[i] /= Float(sum) }
            return kernel
        }
    }
}
