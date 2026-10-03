import CoreGraphics
import Foundation

/// What the live-view rangefinder should draw. The mirror is up, so the body cannot say front or back. Direction is learned from the ring: the arrow stays on the side that is getting sharper, and it flips when that turn goes soft.
enum FocusAim: Equatable {
    case locked
    case lost
    /// side -1 draws the arrow on the left, +1 on the right. amount 1 is a short miss, 2 is a long one.
    case turn(side: Int, amount: Int)
}

enum FocusMeter {
    /// Mean edge strength in the center of one body. The center is the spot the brackets mark.
    static func score(_ image: CGImage) -> Double {
        let w = 48
        let h = 32
        let cw = max(8, image.width * 36 / 100)
        let ch = max(8, image.height * 36 / 100)
        let crop = CGRect(x: (image.width - cw) / 2, y: (image.height - ch) / 2, width: cw, height: ch)
        guard let piece = image.cropping(to: crop) else { return 0 }
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.interpolationQuality = .low
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: w, height: h))
        var luma = 0.0
        var edge = 0.0
        var n = 0
        func yAt(_ i: Int) -> Double {
            Double(px[i]) * 0.3 + Double(px[i + 1]) * 0.59 + Double(px[i + 2]) * 0.11
        }
        for row in 0..<(h - 1) {
            for col in 0..<(w - 1) {
                let i = (row * w + col) * 4
                let y = yAt(i)
                luma += y
                edge += abs(y - yAt(i + 4)) + abs(y - yAt(i + w * 4))
                n += 1
            }
        }
        guard n > 0 else { return 0 }
        if luma / Double(n) < 8 { return 0 }
        return edge / Double(n)
    }
}

/// One body's focus travel. A still frame stays lost until the ring moves, because a single soft picture does not say which way to turn.
final class FocusDial {
    private var samples: [(t: CFAbsoluteTime, s: Double)] = []
    private var heading = 0
    private var arrived = 0
    private var improving = false
    private var best = 0.0
    private var upRun = 0
    private var downRun = 0

    func reset() {
        samples = []
        heading = 0
        arrived = 0
        improving = false
        best = 0
        upRun = 0
        downRun = 0
    }

    func push(_ sharpness: Double) -> FocusAim {
        let now = CFAbsoluteTimeGetCurrent()
        samples.append((now, sharpness))
        samples.removeAll { now - $0.t > 1.6 }
        best = max(sharpness, best * 0.997)
        let past = samples.last { now - $0.t >= 0.18 } ?? samples.first
        let slope = sharpness - (past?.s ?? sharpness)
        let trip = max(0.55, best * 0.04)
        let near = sharpness >= 6.5 && sharpness >= best * 0.93 && abs(slope) < trip
        let seenSoft = samples.contains { best - $0.s > trip * 2 }
        if near && seenSoft {
            if heading != 0 { arrived = heading }
            improving = false
            upRun = 0
            downRun = 0
            return .locked
        }
        if slope > trip {
            upRun += 1
            downRun = 0
            if upRun >= 2 {
                if heading == 0 { heading = 1 }
                improving = true
            }
        } else if slope < -trip {
            downRun += 1
            upRun = 0
            if downRun >= 2 {
                if heading == 0 {
                    heading = arrived == 0 ? -1 : -arrived
                } else if improving {
                    heading = -heading
                }
                improving = false
            }
        } else {
            upRun = 0
            downRun = 0
        }
        guard heading != 0 else { return .lost }
        let amount = sharpness >= best * 0.78 ? 1 : 2
        return .turn(side: heading, amount: amount)
    }
}
