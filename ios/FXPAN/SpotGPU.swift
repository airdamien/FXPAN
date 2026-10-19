import Foundation
import Metal

/// The same total-variation tiles as the CPU path, kept on the GPU for every pass. A miss falls back to vDSP.
enum SpotGPU {
    private static let n = 512
    private static let count = 512 * 512
    private static let margin = 96
    private static let core = 512 - 2 * 96
    private static let batch = 4

    static func deconvolve(_ plane: [Float], _ w: Int, _ h: Int, sigma: Float) -> [Float]? {
        guard w > 64, h > 64, let gpu = GPU.shared else { return nil }
        let started = CFAbsoluteTimeGetCurrent()
        guard let out = gpu.run(plane, w: w, h: h, sigma: sigma) else { return nil }
        Trace.line(String(format: "FXPAN spot metal %.2fs", CFAbsoluteTimeGetCurrent() - started))
        return out
    }

    private final class GPU {
        static let shared: GPU? = GPU()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let fft: MTLComputePipelineState
        let transpose: MTLComputePipelineState
        let pack: MTLComputePipelineState
        let taper: MTLComputePipelineState
        let mulH: MTLComputePipelineState
        let shrink: MTLComputePipelineState
        let solve: MTLComputePipelineState
        let take: MTLComputePipelineState

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
            let library: MTLLibrary?
            if let path = ProcessInfo.processInfo.environment["FXPAN_SPOT_METALLIB"] {
                library = try? device.makeLibrary(URL: URL(fileURLWithPath: path))
            } else {
                library = device.makeDefaultLibrary()
            }
            guard let library else { return nil }
            func pipe(_ name: String) -> MTLComputePipelineState? {
                guard let fn = library.makeFunction(name: name) else { return nil }
                return try? device.makeComputePipelineState(function: fn)
            }
            guard let fft = pipe("spotFFTRows"), let transpose = pipe("spotTranspose"), let pack = pipe("spotPackReal"),
                  let taper = pipe("spotTaper"), let mulH = pipe("spotMulConjH"), let shrink = pipe("spotShrink"),
                  let solve = pipe("spotSolve"), let take = pipe("spotTakeReal") else { return nil }
            self.device = device
            self.queue = queue
            self.fft = fft
            self.transpose = transpose
            self.pack = pack
            self.taper = taper
            self.mulH = mulH
            self.shrink = shrink
            self.solve = solve
            self.take = take
        }

        func run(_ plane: [Float], w: Int, h: Int, sigma: Float) -> [Float]? {
            guard let ops = operators(sigma) else { return nil }
            let tilesX = (w + core - 1) / core
            let tilesY = (h + core - 1) / core
            let total = tilesX * tilesY
            guard total > 0, total < 400 else { return nil }
            var out = [Float](repeating: 0, count: w * h)
            var done = 0
            while done < total {
                let nTiles = min(batch, total - done)
                guard let tiles = restore(plane, w: w, h: h, ops: ops, tilesX: tilesX, first: done, count: nTiles) else { return nil }
                for t in 0..<nTiles {
                    let index = done + t
                    let tx = (index % tilesX) * core - margin
                    let ty = (index / tilesX) * core - margin
                    let base = t * count
                    for y in margin..<(n - margin) {
                        let dy = ty + y
                        guard dy >= 0, dy < h else { continue }
                        for x in margin..<(n - margin) {
                            let dx = tx + x
                            guard dx >= 0, dx < w else { continue }
                            out[dy * w + dx] = tiles[base + y * n + x]
                        }
                    }
                }
                done += nTiles
            }
            return out
        }

        private struct Ops {
            let h: MTLBuffer
            let dx: MTLBuffer
            let dy: MTLBuffer
            let h2: MTLBuffer
            let d2: MTLBuffer
        }

        private func operators(_ sigma: Float) -> Ops? {
            var space = [Float](repeating: 0, count: count)
            let rad = Int(ceil(sigma * 4))
            var sum: Float = 0
            for dy in -rad...rad {
                for dx in -rad...rad {
                    let v = exp(-0.5 * Float(dx * dx + dy * dy) / (sigma * sigma))
                    space[((dy + n) % n) * n + (dx + n) % n] += v
                    sum += v
                }
            }
            guard sum > 0, let hSpec = fftReal(&space) else { return nil }
            for i in space.indices { space[i] = 0 }
            space[0] = -1
            space[1] = 1
            guard let dxSpec = fftReal(&space) else { return nil }
            for i in space.indices { space[i] = 0 }
            space[0] = -1
            space[n] = 1
            guard let dySpec = fftReal(&space) else { return nil }
            let hNorm = hSpec.map { $0 / sum }
            var h2 = [Float](repeating: 0, count: count)
            var d2 = [Float](repeating: 0, count: count)
            for i in 0..<count {
                let hh = hNorm[i]
                h2[i] = hh.x * hh.x + hh.y * hh.y
                let d = dxSpec[i]
                let e = dySpec[i]
                d2[i] = d.x * d.x + d.y * d.y + e.x * e.x + e.y * e.y
            }
            guard let hBuf = hNorm.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared) }),
                  let dxBuf = dxSpec.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared) }),
                  let dyBuf = dySpec.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared) }),
                  let h2Buf = h2.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * MemoryLayout<Float>.stride, options: .storageModeShared) }),
                  let d2Buf = d2.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * MemoryLayout<Float>.stride, options: .storageModeShared) }) else { return nil }
            return Ops(h: hBuf, dx: dxBuf, dy: dyBuf, h2: h2Buf, d2: d2Buf)
        }

        /// Forward FFT of one real tile. The buffer is one tile and is overwritten.
        private func fftReal(_ space: inout [Float]) -> [SIMD2<Float>]? {
            guard let real = space.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: count * MemoryLayout<Float>.stride, options: .storageModeShared) }),
                  let spec = device.makeBuffer(length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
                  let tmp = device.makeBuffer(length: count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
                  let enc = queue.makeCommandBuffer() else { return nil }
            encodePack(enc, real: real, spec: spec, tiles: 1)
            encodeFFT(enc, spec, tmp, tiles: 1, sign: 1)
            enc.commit()
            enc.waitUntilCompleted()
            guard enc.status == .completed else { return nil }
            let ptr = spec.contents().bindMemory(to: SIMD2<Float>.self, capacity: count)
            return Array(UnsafeBufferPointer(start: ptr, count: count))
        }

        private func restore(_ plane: [Float], w: Int, h: Int, ops: Ops, tilesX: Int, first: Int, count nTiles: Int) -> [Float]? {
            let bytes = nTiles * count
            var packed = [Float](repeating: 0, count: bytes)
            var means = [Float](repeating: 0, count: nTiles)
            for t in 0..<nTiles {
                let index = first + t
                let tx = (index % tilesX) * core - margin
                let ty = (index / tilesX) * core - margin
                var mean: Float = 0
                let base = t * count
                for y in 0..<n {
                    let sy = min(h - 1, max(0, ty + y))
                    for x in 0..<n {
                        let v = plane[sy * w + min(w - 1, max(0, tx + x))]
                        packed[base + y * n + x] = v
                        mean += v
                    }
                }
                means[t] = mean / Float(count)
            }
            guard let real = packed.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: bytes * MemoryLayout<Float>.stride, options: .storageModeShared) }),
                  let zx = device.makeBuffer(length: bytes * MemoryLayout<Float>.stride, options: .storageModeShared),
                  let zy = device.makeBuffer(length: bytes * MemoryLayout<Float>.stride, options: .storageModeShared),
                  let spec = device.makeBuffer(length: bytes * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
                  let tmp = device.makeBuffer(length: bytes * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
                  let zxs = device.makeBuffer(length: bytes * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
                  let zys = device.makeBuffer(length: bytes * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared),
                  let meanBuf = means.withUnsafeBytes({ device.makeBuffer(bytes: $0.baseAddress!, length: nTiles * MemoryLayout<Float>.stride, options: .storageModeShared) }),
                  let enc = queue.makeCommandBuffer() else { return nil }

            encodeTaper(enc, real: real, means: meanBuf, tiles: nTiles)
            encodePack(enc, real: real, spec: spec, tiles: nTiles)
            encodeFFT(enc, spec, tmp, tiles: nTiles, sign: 1)
            encodeMulH(enc, spec: spec, tiles: nTiles, ops: ops)
            // spec now holds conj(H) Y and stays there. The estimate starts as the tapered tile.
            var beta: Float = 0.03
            for _ in 0..<8 {
                let threshold = 1 / beta
                encodeShrink(enc, real: real, zx: zx, zy: zy, threshold: threshold, tiles: nTiles)
                encodePack(enc, real: zx, spec: zxs, tiles: nTiles)
                encodeFFT(enc, zxs, tmp, tiles: nTiles, sign: 1)
                encodePack(enc, real: zy, spec: zys, tiles: nTiles)
                encodeFFT(enc, zys, tmp, tiles: nTiles, sign: 1)
                encodeSolve(enc, zx: zxs, zy: zys, hy: spec, out: tmp, lambda: 0.3, beta: beta, tiles: nTiles, ops: ops)
                encodeFFT(enc, tmp, zxs, tiles: nTiles, sign: -1)
                encodeTake(enc, spec: tmp, real: real, scale: 1 / Float(count), tiles: nTiles)
                beta *= 2
            }
            enc.commit()
            enc.waitUntilCompleted()
            guard enc.status == .completed else { return nil }
            let ptr = real.contents().bindMemory(to: Float.self, capacity: bytes)
            return Array(UnsafeBufferPointer(start: ptr, count: bytes))
        }

        private func encodeFFT(_ buf: MTLCommandBuffer, _ spec: MTLBuffer, _ tmp: MTLBuffer, tiles: Int, sign: Int) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(fft)
            enc.setBuffer(spec, offset: 0, index: 0)
            var s = Int32(sign)
            enc.setBytes(&s, length: 4, index: 1)
            enc.dispatchThreadgroups(MTLSize(width: n * tiles, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: n, height: 1, depth: 1))
            enc.endEncoding()
            guard let tr = buf.makeComputeCommandEncoder() else { return }
            tr.setComputePipelineState(transpose)
            tr.setBuffer(spec, offset: 0, index: 0)
            tr.setBuffer(tmp, offset: 0, index: 1)
            var t = UInt32(tiles)
            tr.setBytes(&t, length: 4, index: 2)
            tr.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            tr.endEncoding()
            guard let enc2 = buf.makeComputeCommandEncoder() else { return }
            enc2.setComputePipelineState(fft)
            enc2.setBuffer(tmp, offset: 0, index: 0)
            enc2.setBytes(&s, length: 4, index: 1)
            enc2.dispatchThreadgroups(MTLSize(width: n * tiles, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: n, height: 1, depth: 1))
            enc2.endEncoding()
            guard let tr2 = buf.makeComputeCommandEncoder() else { return }
            tr2.setComputePipelineState(transpose)
            tr2.setBuffer(tmp, offset: 0, index: 0)
            tr2.setBuffer(spec, offset: 0, index: 1)
            tr2.setBytes(&t, length: 4, index: 2)
            tr2.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            tr2.endEncoding()
        }

        private func encodePack(_ buf: MTLCommandBuffer, real: MTLBuffer, spec: MTLBuffer, tiles: Int) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(pack)
            enc.setBuffer(real, offset: 0, index: 0)
            enc.setBuffer(spec, offset: 0, index: 1)
            var t = UInt32(tiles)
            enc.setBytes(&t, length: 4, index: 2)
            enc.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            enc.endEncoding()
        }

        private func encodeTaper(_ buf: MTLCommandBuffer, real: MTLBuffer, means: MTLBuffer, tiles: Int) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(taper)
            enc.setBuffer(real, offset: 0, index: 0)
            enc.setBuffer(means, offset: 0, index: 1)
            var t = UInt32(tiles)
            enc.setBytes(&t, length: 4, index: 2)
            enc.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            enc.endEncoding()
        }

        private func encodeMulH(_ buf: MTLCommandBuffer, spec: MTLBuffer, tiles: Int, ops: Ops) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(mulH)
            enc.setBuffer(spec, offset: 0, index: 0)
            enc.setBuffer(ops.h, offset: 0, index: 1)
            var t = UInt32(tiles)
            enc.setBytes(&t, length: 4, index: 2)
            enc.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            enc.endEncoding()
        }

        private func encodeShrink(_ buf: MTLCommandBuffer, real: MTLBuffer, zx: MTLBuffer, zy: MTLBuffer, threshold: Float, tiles: Int) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(shrink)
            enc.setBuffer(real, offset: 0, index: 0)
            enc.setBuffer(zx, offset: 0, index: 1)
            enc.setBuffer(zy, offset: 0, index: 2)
            var th = threshold
            enc.setBytes(&th, length: 4, index: 3)
            var t = UInt32(tiles)
            enc.setBytes(&t, length: 4, index: 4)
            enc.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            enc.endEncoding()
        }

        private func encodeSolve(_ buf: MTLCommandBuffer, zx: MTLBuffer, zy: MTLBuffer, hy: MTLBuffer, out: MTLBuffer, lambda: Float, beta: Float, tiles: Int, ops: Ops) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(solve)
            enc.setBuffer(zx, offset: 0, index: 0)
            enc.setBuffer(zy, offset: 0, index: 1)
            enc.setBuffer(hy, offset: 0, index: 2)
            enc.setBuffer(ops.dx, offset: 0, index: 3)
            enc.setBuffer(ops.dy, offset: 0, index: 4)
            enc.setBuffer(ops.h2, offset: 0, index: 5)
            enc.setBuffer(ops.d2, offset: 0, index: 6)
            enc.setBuffer(out, offset: 0, index: 7)
            var lam = lambda
            var bet = beta
            var t = UInt32(tiles)
            enc.setBytes(&lam, length: 4, index: 8)
            enc.setBytes(&bet, length: 4, index: 9)
            enc.setBytes(&t, length: 4, index: 10)
            enc.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            enc.endEncoding()
        }

        private func encodeTake(_ buf: MTLCommandBuffer, spec: MTLBuffer, real: MTLBuffer, scale: Float, tiles: Int) {
            guard let enc = buf.makeComputeCommandEncoder() else { return }
            enc.setComputePipelineState(take)
            enc.setBuffer(spec, offset: 0, index: 0)
            enc.setBuffer(real, offset: 0, index: 1)
            var sc = scale
            var t = UInt32(tiles)
            enc.setBytes(&sc, length: 4, index: 2)
            enc.setBytes(&t, length: 4, index: 3)
            enc.dispatchThreads(MTLSize(width: n, height: n, depth: tiles), threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
            enc.endEncoding()
        }
    }
}
