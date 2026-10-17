import CoreGraphics
import Foundation
import Metal
import simd

/// Full-resolution bilinear warp on the GPU. The CPU loop stays for the Apple menu switch and for a device that refuses the buffer.
enum WarpGPU {
    struct Job {
        var sw: UInt32
        var sh: UInt32
        var cw: UInt32
        var ch: UInt32
        var x0: Float
        var y0: Float
        var a: Float
        var b: Float
        var tx: Float
        var ty: Float
        var kind: UInt32
        var seamX0: Float
        var seamX1: Float
        var refH: Float
        var stripDx0: SIMD4<Float>
        var stripDx1: SIMD4<Float>
        var stripDx8: Float
        var stripDy0: SIMD4<Float>
        var stripDy1: SIMD4<Float>
        var stripDy8: Float
    }

    static func frames(r: Hugin.RGBA, t: Hugin.RGBA, x0: Double, y0: Double, cw: Int, ch: Int, mt: Hugin.Affine) -> (r: [UInt8], t: [UInt8])? {
        guard cw > 0, ch > 0, let gpu = GPU.shared else { return nil }
        let started = CFAbsoluteTimeGetCurrent()
        let zero = Hugin.Affine(a: 1, b: 0, tx: 0, ty: 0)
        guard let rpx = gpu.sample(r, cw: cw, ch: ch, x0: Float(x0), y0: Float(y0), mt: zero, kind: 0),
              let tpx = gpu.sample(t, cw: cw, ch: ch, x0: 0, y0: 0, mt: mt, kind: 1) else {
            return nil
        }
        print(String(format: "FXPAN warp metal %dx%d %.2fs", cw, ch, CFAbsoluteTimeGetCurrent() - started))
        return (rpx, tpx)
    }

    private final class GPU {
        static let shared: GPU? = GPU()
        let device: MTLDevice
        let queue: MTLCommandQueue
        let pipe: MTLComputePipelineState

        init?() {
            guard let device = MTLCreateSystemDefaultDevice(),
                  let queue = device.makeCommandQueue(),
                  let library = device.makeDefaultLibrary(),
                  let fn = library.makeFunction(name: "fxpanWarp"),
                  let pipe = try? device.makeComputePipelineState(function: fn) else { return nil }
            self.device = device
            self.queue = queue
            self.pipe = pipe
        }

        func sample(_ img: Hugin.RGBA, cw: Int, ch: Int, x0: Float, y0: Float, mt: Hugin.Affine, kind: UInt32) -> [UInt8]? {
            let srcBytes = img.w * img.h * 4
            let dstBytes = cw * ch * 4
            guard srcBytes > 0, dstBytes > 0, dstBytes <= device.maxBufferLength, srcBytes <= device.maxBufferLength else { return nil }
            let src: MTLBuffer? = img.px.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return nil }
                return device.makeBuffer(bytes: base, length: srcBytes, options: .storageModeShared)
            }
            guard let src, let dst = device.makeBuffer(length: dstBytes, options: .storageModeShared),
                  let cmd = queue.makeCommandBuffer(),
                  let enc = cmd.makeComputeCommandEncoder() else { return nil }
            let dx = mt.stripDx.count >= 9 ? mt.stripDx.map { Float($0) } : Array(repeating: Float(0), count: 9)
            let dy = mt.stripDy.count >= 9 ? mt.stripDy.map { Float($0) } : Array(repeating: Float(0), count: 9)
            var job = Job(
                sw: UInt32(img.w), sh: UInt32(img.h), cw: UInt32(cw), ch: UInt32(ch),
                x0: x0, y0: y0, a: Float(mt.a), b: Float(mt.b), tx: Float(mt.tx), ty: Float(mt.ty), kind: kind,
                seamX0: Float(mt.seamX0), seamX1: Float(mt.seamX1), refH: Float(mt.refH),
                stripDx0: SIMD4<Float>(dx[0], dx[1], dx[2], dx[3]),
                stripDx1: SIMD4<Float>(dx[4], dx[5], dx[6], dx[7]),
                stripDx8: dx[8],
                stripDy0: SIMD4<Float>(dy[0], dy[1], dy[2], dy[3]),
                stripDy1: SIMD4<Float>(dy[4], dy[5], dy[6], dy[7]),
                stripDy8: dy[8]
            )
            enc.setComputePipelineState(pipe)
            enc.setBuffer(src, offset: 0, index: 0)
            enc.setBuffer(dst, offset: 0, index: 1)
            enc.setBytes(&job, length: MemoryLayout<Job>.stride, index: 2)
            let width = pipe.threadExecutionWidth
            let height = max(1, pipe.maxTotalThreadsPerThreadgroup / width)
            enc.dispatchThreads(
                MTLSize(width: cw, height: ch, depth: 1),
                threadsPerThreadgroup: MTLSize(width: width, height: height, depth: 1)
            )
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()
            guard cmd.status == .completed else {
                print("FXPAN warp metal \(cmd.status.rawValue)")
                return nil
            }
            var out = [UInt8](repeating: 0, count: dstBytes)
            out.withUnsafeMutableBytes { raw in
                raw.copyMemory(from: UnsafeRawBufferPointer(start: dst.contents(), count: dstBytes))
            }
            return out
        }
    }
}
