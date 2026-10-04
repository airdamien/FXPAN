import CoreGraphics
import Foundation

/// What the live-view rangefinder should draw. The mirror is up, so the body cannot say front or back. Direction is learned from the ring: the arrow stays on the side that is getting sharper, and it flips when that turn goes soft.
enum FocusAim: Equatable {
    case locked
    case lost
    /// side -1 draws the arrow on the left, +1 on the right. amount 1 is a short miss, 2 is a long one.
    case turn(side: Int, amount: Int)
}

/// Which body a point on the panorama belongs to. The overlap belongs to both.
enum FocusPlace: Equatable {
    case r
    case t
    case both
}

struct FocusRead: Equatable {
    var score: Double?
    var box: CGRect?
    var sharp: CGRect?
    var place: FocusPlace = .both
}

enum FocusMeter {
    /// A window around a tap, in panorama units.
    static func window(around point: CGPoint) -> CGRect {
        let w: CGFloat = 0.18
        let h: CGFloat = 0.46
        let x = min(1 - w, max(0, point.x - w / 2))
        let y = min(1 - h, max(0, point.y - h / 2))
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// R is the left of the stitch, T the right. A point in the overlap watches both bodies.
    static func place(x: CGFloat, overlap: Double, only: FocusPlace?) -> FocusPlace {
        if let only, only != .both { return only }
        let span = 2 - overlap
        let unit = Double(min(1, max(0, x))) * span
        let onR = unit <= 1
        let onT = unit >= 1 - overlap
        if onR && onT { return .both }
        return onT ? .t : .r
    }

    /// Sharpest cluster in the panorama, plus the score of the place being watched.
    static func read(_ image: CGImage, aim: CGPoint?, overlap: Double, only: FocusPlace?) -> FocusRead {
        let sharp = survey(image)
        let box = aim.map { window(around: $0) } ?? sharp
        guard let box else { return FocusRead() }
        let value = score(image, in: box)
        return FocusRead(
            score: value > 0 ? value : nil,
            box: box,
            sharp: sharp,
            place: place(x: box.midX, overlap: overlap, only: only)
        )
    }

    /// Mean edge strength inside a normalized rect of the panorama.
    static func score(_ image: CGImage, in unit: CGRect) -> Double {
        let w = image.width
        let h = image.height
        guard w > 16, h > 16 else { return 0 }
        let x = min(w - 8, max(0, Int(unit.minX * CGFloat(w))))
        let y = min(h - 8, max(0, Int(unit.minY * CGFloat(h))))
        let cw = min(w - x, max(8, Int(unit.width * CGFloat(w))))
        let ch = min(h - y, max(8, Int(unit.height * CGFloat(h))))
        let crop = CGRect(x: x, y: y, width: cw, height: ch)
        guard let piece = image.cropping(to: crop) else { return 0 }
        let dw = 48
        let dh = 32
        var px = [UInt8](repeating: 0, count: dw * dh * 4)
        guard let ctx = CGContext(
            data: &px, width: dw, height: dh, bitsPerComponent: 8, bytesPerRow: dw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        ctx.interpolationQuality = .low
        ctx.draw(piece, in: CGRect(x: 0, y: 0, width: dw, height: dh))
        return bufferScore(px, stride: dw, x: 0, y: 0, w: dw, h: dh)
    }

    /// Bounding box of the sharpest neighborhood, in panorama units. Nil when the frame is blank.
    private static func survey(_ image: CGImage) -> CGRect? {
        let cols = 12
        let rows = 4
        let gw = 8
        let gh = 8
        let width = cols * gw
        let height = rows * gh
        var px = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var cell = [Double](repeating: 0, count: cols * rows)
        var best = 0.0
        var bestI = 0
        for row in 0..<rows {
            for col in 0..<cols {
                let i = row * cols + col
                let value = bufferScore(px, stride: width, x: col * gw, y: row * gh, w: gw, h: gh)
                cell[i] = value
                if value > best {
                    best = value
                    bestI = i
                }
            }
        }
        guard best > 0 else { return nil }
        let peakCol = bestI % cols
        let peakRow = bestI / cols
        let gate = best * 0.62
        var minC = peakCol
        var maxC = peakCol
        var minR = peakRow
        var maxR = peakRow
        for row in 0..<rows {
            for col in 0..<cols {
                if max(abs(col - peakCol), abs(row - peakRow)) > 2 { continue }
                if cell[row * cols + col] < gate { continue }
                minC = min(minC, col)
                maxC = max(maxC, col)
                minR = min(minR, row)
                maxR = max(maxR, row)
            }
        }
        let pad: CGFloat = 0.35
        let x = max(0, (CGFloat(minC) - pad) / CGFloat(cols))
        let y = max(0, (CGFloat(minR) - pad) / CGFloat(rows))
        let boxW = min(1 - x, (CGFloat(maxC - minC + 1) + pad * 2) / CGFloat(cols))
        let boxH = min(1 - y, (CGFloat(maxR - minR + 1) + pad * 2) / CGFloat(rows))
        return CGRect(x: x, y: y, width: boxW, height: boxH)
    }

    private static func bufferScore(_ px: [UInt8], stride: Int, x: Int, y: Int, w: Int, h: Int) -> Double {
        var luma = 0.0
        var edge = 0.0
        var n = 0
        func tone(_ i: Int) -> Double {
            Double(px[i]) * 0.3 + Double(px[i + 1]) * 0.59 + Double(px[i + 2]) * 0.11
        }
        for row in y..<(y + h - 1) {
            for col in x..<(x + w - 1) {
                let i = (row * stride + col) * 4
                let sample = tone(i)
                luma += sample
                edge += abs(sample - tone(i + 4)) + abs(sample - tone(((row + 1) * stride + col) * 4))
                n += 1
            }
        }
        guard n > 0, luma / Double(n) >= 8 else { return 0 }
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
