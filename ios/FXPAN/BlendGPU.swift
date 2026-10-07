import Foundation
import Metal

/// The band blend and the per-row color match. The CPU path stays if a texture or the device refuses the frame.
enum BlendGPU {
    static func multiband(r: [UInt8], t: [UInt8], w: Int, h: Int, bands: Int) -> [UInt8]? {
        guard w >= 16, h >= 16, w <= 16384, h <= 16384, bands >= 1, let gpu = GPU.shared else { return nil }
        let started = CFAbsoluteTimeGetCurrent()
        guard let out = gpu.multiband(r: r, t: t, w: w, h: h, bands: bands) else { return nil }
        print(String(format: "FXPAN blend metal %dx%d bands=%d %.2fs", w, h, bands, CFAbsoluteTimeGetCurrent() - started))
        return out
    }

    /// Darken each row by the scales already fit on the overlap. False leaves the CPU loop in place.
    static func darken(_ r: inout [UInt8], _ t: inout [UInt8], w: Int, h: Int, scaleR: [Float], scaleT: [Float]) -> Bool {
        guard w > 0, h > 0, scaleR.count == h * 3, scaleT.count == h * 3, let gpu = GPU.shared else { return false }
        let started = CFAbsoluteTimeGetCurrent()
        guard gpu.darken(&r, &t, w: w, h: h, scaleR: scaleR, scaleT: scaleT) else { return false }
        print(String(format: "FXPAN balance metal %dx%d %.2fs", w, h, CFAbsoluteTimeGetCurrent() - started))
        return true
    }

    private final class GPU {
        static let shared: GPU? = GPU()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let blurPipe: MTLComputePipelineState
        let evenPipe: MTLComputePipelineState
        let expandPipe: MTLComputePipelineState
        let subPipe: MTLComputePipelineState
        let addPipe: MTLComputePipelineState
        let maskPipe: MTLComputePipelineState
        let extractPipe: MTLComputePipelineState
        let fillHPipe: MTLComputePipelineState
        let fillVPipe: MTLComputePipelineState
        let floorPipe: MTLComputePipelineState
        let packPipe: MTLComputePipelineState
        let balancePipe: MTLComputePipelineState

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let library: MTLLibrary?
            if let path = ProcessInfo.processInfo.environment["FXPAN_BLEND_METALLIB"] {
                library = try? device.makeLibrary(URL: URL(fileURLWithPath: path))
            } else {
                library = device.makeDefaultLibrary()
            }
            guard let library else { return nil }
            func pipe(_ name: String) -> MTLComputePipelineState? {
                guard let fn = library.makeFunction(name: name) else {
                    print("FXPAN blend metal missing \(name)")
                    return nil
                }
                do { return try device.makeComputePipelineState(function: fn) }
                catch {
                    print("FXPAN blend metal \(name) \(error.localizedDescription)")
                    return nil
                }
            }
            guard let blurPipe = pipe("fxpanBlur5"), let evenPipe = pipe("fxpanTakeEven"), let expandPipe = pipe("fxpanExpand"),
                  let subPipe = pipe("fxpanSub"), let addPipe = pipe("fxpanAdd"), let maskPipe = pipe("fxpanMask"),
                  let extractPipe = pipe("fxpanExtract"), let fillHPipe = pipe("fxpanFillH"), let fillVPipe = pipe("fxpanFillV"),
                  let floorPipe = pipe("fxpanFloor"), let packPipe = pipe("fxpanPack"), let balancePipe = pipe("fxpanBalance") else { return nil }
            self.device = device
            self.queue = queue
            self.blurPipe = blurPipe
            self.evenPipe = evenPipe
            self.expandPipe = expandPipe
            self.subPipe = subPipe
            self.addPipe = addPipe
            self.maskPipe = maskPipe
            self.extractPipe = extractPipe
            self.fillHPipe = fillHPipe
            self.fillVPipe = fillVPipe
            self.floorPipe = floorPipe
            self.packPipe = packPipe
            self.balancePipe = balancePipe
        }

        func multiband(r: [UInt8], t: [UInt8], w: Int, h: Int, bands: Int) -> [UInt8]? {
            let seamWeight = Self.seam(r, t, w, h)
            guard let rTex = rgba(r, w, h), let tTex = rgba(t, w, h), let wTex = plane(seamWeight, w, h) else { return nil }
            let wPyr = gauss(wTex, bands: bands)
            guard !wPyr.isEmpty else { return nil }
            let outBytes = w * h * 4
            guard outBytes <= device.maxBufferLength, let outBuf = device.makeBuffer(length: outBytes, options: .storageModeShared) else { return nil }
            memset(outBuf.contents(), 0, outBytes)
            for channel in 0..<3 {
                guard let rf = filled(rTex, channel: channel), let tf = filled(tTex, channel: channel) else { return nil }
                guard var rLevels = laplacian(rf, bands: bands), var tLevels = laplacian(tf, bands: bands) else { return nil }
                guard applyWeight(&rLevels, wPyr, invert: false), applyWeight(&tLevels, wPyr, invert: true) else { return nil }
                guard combine(&rLevels, tLevels) else { return nil }
                guard let collapsed = collapse(rLevels) else { return nil }
                guard pack(rTex, tTex, collapsed, outBuf, channel: channel, w: w, h: h) else { return nil }
            }
            var out = [UInt8](repeating: 0, count: outBytes)
            out.withUnsafeMutableBytes { raw in
                raw.copyMemory(from: UnsafeRawBufferPointer(start: outBuf.contents(), count: outBytes))
            }
            return out
        }

        func darken(_ r: inout [UInt8], _ t: inout [UInt8], w: Int, h: Int, scaleR: [Float], scaleT: [Float]) -> Bool {
            guard let rTex = rgba(r, w, h), let tTex = rgba(t, w, h) else { return false }
            guard apply(rTex, scaleR, w: w, h: h), apply(tTex, scaleT, w: w, h: h) else { return false }
            guard read(rTex, into: &r, w: w, h: h), read(tTex, into: &t, w: w, h: h) else { return false }
            return true
        }

        private func gauss(_ src: MTLTexture, bands: Int) -> [MTLTexture] {
            var levels = [src]
            var cw = src.width
            var ch = src.height
            while levels.count < bands {
                let nw = cw / 2
                let nh = ch / 2
                if nw < 8 || nh < 8 { break }
                guard let down = pyrDown(levels[levels.count - 1], nw, nh) else { return [] }
                levels.append(down)
                cw = nw
                ch = nh
            }
            return levels
        }

        private func laplacian(_ src: MTLTexture, bands: Int) -> [MTLTexture]? {
            var levels = gauss(src, bands: bands)
            guard !levels.isEmpty else { return nil }
            let last = levels.count - 1
            for level in 0..<last {
                guard let up = pyrUp(levels[level + 1], levels[level].width, levels[level].height),
                      let diff = binary(levels[level], up, pipe: subPipe) else { return nil }
                levels[level] = diff
            }
            return levels
        }

        private func applyWeight(_ levels: inout [MTLTexture], _ weights: [MTLTexture], invert: Bool) -> Bool {
            for level in 0..<levels.count where level < weights.count {
                guard levels[level].width == weights[level].width, levels[level].height == weights[level].height,
                      let scaled = mask(levels[level], weights[level], invert: invert) else { return false }
                levels[level] = scaled
            }
            return true
        }

        private func combine(_ acc: inout [MTLTexture], _ other: [MTLTexture]) -> Bool {
            let n = min(acc.count, other.count)
            for level in 0..<n {
                guard acc[level].width == other[level].width,
                      let sum = binary(acc[level], other[level], pipe: addPipe) else { return false }
                acc[level] = sum
            }
            return true
        }

        private func collapse(_ levels: [MTLTexture]) -> MTLTexture? {
            let last = levels.count - 1
            guard last >= 0 else { return nil }
            var acc = levels[last]
            if last == 0 { return acc }
            for level in stride(from: last - 1, through: 0, by: -1) {
                guard let up = pyrUp(acc, levels[level].width, levels[level].height),
                      let sum = binary(up, levels[level], pipe: addPipe) else { return nil }
                acc = sum
            }
            return acc
        }

        private func pyrDown(_ src: MTLTexture, _ nw: Int, _ nh: Int) -> MTLTexture? {
            guard let blurred = make(src.width, src.height), let dst = make(nw, nh),
                  let cmd = queue.makeCommandBuffer(),
                  let encB = cmd.makeComputeCommandEncoder() else { return nil }
            var gain: Float = 1
            encB.setComputePipelineState(blurPipe)
            encB.setTexture(src, index: 0)
            encB.setTexture(blurred, index: 1)
            encB.setBytes(&gain, length: MemoryLayout<Float>.stride, index: 0)
            dispatch(encB, blurPipe, src.width, src.height)
            encB.endEncoding()
            guard let encS = cmd.makeComputeCommandEncoder() else { return nil }
            encS.setComputePipelineState(evenPipe)
            encS.setTexture(blurred, index: 0)
            encS.setTexture(dst, index: 1)
            dispatch(encS, evenPipe, nw, nh)
            encS.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { return nil }
            return dst
        }

        private func pyrUp(_ src: MTLTexture, _ tw: Int, _ th: Int) -> MTLTexture? {
            guard let expanded = make(tw, th), let dst = make(tw, th),
                  let cmd = queue.makeCommandBuffer(),
                  let encE = cmd.makeComputeCommandEncoder() else { return nil }
            encE.setComputePipelineState(expandPipe)
            encE.setTexture(src, index: 0)
            encE.setTexture(expanded, index: 1)
            dispatch(encE, expandPipe, tw, th)
            encE.endEncoding()
            guard let encB = cmd.makeComputeCommandEncoder() else { return nil }
            var gain: Float = 4
            encB.setComputePipelineState(blurPipe)
            encB.setTexture(expanded, index: 0)
            encB.setTexture(dst, index: 1)
            encB.setBytes(&gain, length: MemoryLayout<Float>.stride, index: 0)
            dispatch(encB, blurPipe, tw, th)
            encB.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else { return nil }
            return dst
        }

        private func binary(_ a: MTLTexture, _ b: MTLTexture, pipe: MTLComputePipelineState) -> MTLTexture? {
            guard a.width == b.width, a.height == b.height, let dst = make(a.width, a.height),
                  let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return nil }
            enc.setComputePipelineState(pipe)
            enc.setTexture(a, index: 0)
            enc.setTexture(b, index: 1)
            enc.setTexture(dst, index: 2)
            dispatch(enc, pipe, a.width, a.height)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            return cmd.status == .completed ? dst : nil
        }

        private func mask(_ src: MTLTexture, _ weights: MTLTexture, invert: Bool) -> MTLTexture? {
            guard let dst = make(src.width, src.height), let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder() else { return nil }
            var flag: UInt32 = invert ? 1 : 0
            enc.setComputePipelineState(maskPipe)
            enc.setTexture(src, index: 0)
            enc.setTexture(weights, index: 1)
            enc.setTexture(dst, index: 2)
            enc.setBytes(&flag, length: MemoryLayout<UInt32>.stride, index: 0)
            dispatch(enc, maskPipe, src.width, src.height)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            return cmd.status == .completed ? dst : nil
        }

        private func filled(_ src: MTLTexture, channel: Int) -> MTLTexture? {
            guard let raw = make(src.width, src.height), let done = make(src.width, src.height),
                  let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return nil }
            var ch = UInt32(channel)
            enc.setComputePipelineState(extractPipe)
            enc.setTexture(src, index: 0)
            enc.setTexture(raw, index: 1)
            enc.setBytes(&ch, length: MemoryLayout<UInt32>.stride, index: 0)
            dispatch(enc, extractPipe, src.width, src.height)
            enc.endEncoding()
            guard let encH = cmd.makeComputeCommandEncoder() else { return nil }
            encH.setComputePipelineState(fillHPipe)
            encH.setTexture(raw, index: 0)
            dispatch(encH, fillHPipe, src.height, 1)
            encH.endEncoding()
            guard let encV = cmd.makeComputeCommandEncoder() else { return nil }
            encV.setComputePipelineState(fillVPipe)
            encV.setTexture(raw, index: 0)
            dispatch(encV, fillVPipe, src.width, 1)
            encV.endEncoding()
            guard let encF = cmd.makeComputeCommandEncoder() else { return nil }
            encF.setComputePipelineState(floorPipe)
            encF.setTexture(raw, index: 0)
            encF.setTexture(done, index: 1)
            dispatch(encF, floorPipe, src.width, src.height)
            encF.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            return cmd.status == .completed ? done : nil
        }

        private func pack(_ r: MTLTexture, _ t: MTLTexture, _ blended: MTLTexture, _ out: MTLBuffer, channel: Int, w: Int, h: Int) -> Bool {
            guard let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return false }
            var job = (UInt32(channel), UInt32(w), UInt32(h), UInt32(0))
            enc.setComputePipelineState(packPipe)
            enc.setTexture(r, index: 0)
            enc.setTexture(t, index: 1)
            enc.setTexture(blended, index: 2)
            enc.setBuffer(out, offset: 0, index: 0)
            enc.setBytes(&job, length: MemoryLayout<(UInt32, UInt32, UInt32, UInt32)>.stride, index: 1)
            dispatch(enc, packPipe, w, h)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            return cmd.status == .completed
        }

        private func apply(_ img: MTLTexture, _ scale: [Float], w: Int, h: Int) -> Bool {
            let bytes = scale.count * MemoryLayout<Float>.stride
            let buf: MTLBuffer? = scale.withUnsafeBytes { raw in
                guard let base = raw.baseAddress, bytes > 0, bytes <= device.maxBufferLength else { return nil }
                return device.makeBuffer(bytes: base, length: bytes, options: .storageModeShared)
            }
            guard let buf, let cmd = queue.makeCommandBuffer(), let enc = cmd.makeComputeCommandEncoder() else { return false }
            enc.setComputePipelineState(balancePipe)
            enc.setTexture(img, index: 0)
            enc.setBuffer(buf, offset: 0, index: 0)
            dispatch(enc, balancePipe, w, h)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            return cmd.status == .completed
        }

        private func read(_ tex: MTLTexture, into px: inout [UInt8], w: Int, h: Int) -> Bool {
            guard px.count >= w * h * 4 else { return false }
            let row = w * 4
            return px.withUnsafeMutableBytes { raw in
                guard let base = raw.baseAddress else { return false }
                tex.getBytes(base, bytesPerRow: row, from: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0)
                return true
            }
        }

        private func rgba(_ px: [UInt8], _ w: Int, _ h: Int) -> MTLTexture? {
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            desc.allowGPUOptimizedContents = false
            guard px.count >= w * h * 4, let tex = device.makeTexture(descriptor: desc) else { return nil }
            px.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * 4)
            }
            return tex
        }

        private func plane(_ px: [Float], _ w: Int, _ h: Int) -> MTLTexture? {
            guard let tex = make(w, h), px.count >= w * h else { return nil }
            px.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: base, bytesPerRow: w * MemoryLayout<Float>.stride)
            }
            return tex
        }

        private func make(_ w: Int, _ h: Int) -> MTLTexture? {
            guard w > 0, h > 0 else { return nil }
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead, .shaderWrite]
            desc.storageMode = .shared
            desc.allowGPUOptimizedContents = false
            return device.makeTexture(descriptor: desc)
        }

        private func dispatch(_ enc: MTLComputeCommandEncoder, _ pipe: MTLComputePipelineState, _ w: Int, _ h: Int) {
            let tw = pipe.threadExecutionWidth
            let th = max(1, pipe.maxTotalThreadsPerThreadgroup / tw)
            enc.dispatchThreads(
                MTLSize(width: max(1, w), height: max(1, h), depth: 1),
                threadsPerThreadgroup: MTLSize(width: min(tw, max(1, w)), height: h == 1 ? 1 : min(th, max(1, h)), depth: 1)
            )
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
            d.withUnsafeMutableBufferPointer { buf in
                guard let p = buf.baseAddress else { return }
                for _ in 0..<2 {
                    for y in 0..<h {
                        let row = p + y * w
                        for x in 0..<w {
                            var v = row[x]
                            if x > 0 { v = min(v, row[x - 1] + 1) }
                            if y > 0 { v = min(v, (p + (y - 1) * w)[x] + 1) }
                            row[x] = v
                        }
                    }
                    for y in stride(from: h - 1, through: 0, by: -1) {
                        let row = p + y * w
                        for x in stride(from: w - 1, through: 0, by: -1) {
                            var v = row[x]
                            if x + 1 < w { v = min(v, row[x + 1] + 1) }
                            if y + 1 < h { v = min(v, (p + (y + 1) * w)[x] + 1) }
                            row[x] = v
                        }
                    }
                }
            }
        }
    }
}
