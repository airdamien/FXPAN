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
    /// Sharpest the watched window has been. A new spot has to beat this, so a uniform blur cannot drag the box onto a leftover edge.
    var holdBest: Double = 0
}

enum FocusMeter {
    private static let cols = 24
    private static let rows = 8

    /// A window around a tap, in panorama units.
    static func window(around point: CGPoint) -> CGRect {
        let w: CGFloat = 0.14
        let h: CGFloat = 0.28
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

    /// Fine detail in the panorama. `hold` is the window already being watched. It stays until some other place is plainly sharper than that window has ever been.
    static func read(_ image: CGImage, aim: CGPoint?, overlap: Double, only: FocusPlace?, hold: CGRect?, holdBest: Double) -> FocusRead {
        guard let map = detail(image) else { return FocusRead(holdBest: holdBest) }
        if let aim {
            let box = window(around: aim)
            let value = mean(map, unit: box)
            return FocusRead(
                score: value > 0.2 ? value : nil,
                box: box,
                sharp: box,
                place: place(x: box.midX, overlap: overlap, only: only),
                holdBest: holdBest
            )
        }
        guard let found = cluster(map) else { return FocusRead(holdBest: holdBest) }
        var box = found.box
        var score = found.score
        var best = max(holdBest, score)
        if let hold {
            let heldScore = mean(map, unit: hold)
            best = max(holdBest, heldScore)
            let plainlySharper = score >= best * 0.45 && score >= heldScore * 1.55
            if !plainlySharper {
                box = hold
                score = heldScore
            } else {
                best = score
            }
        }
        return FocusRead(
            score: score > 0.2 ? score : nil,
            box: box,
            sharp: box,
            place: place(x: box.midX, overlap: overlap, only: only),
            holdBest: best
        )
    }

    private struct Detail {
        var cells: [Double]
        var cols: Int
        var rows: Int
    }

    /// Mean fine detail. A mild blur is subtracted so a soft foreground, which has already lost its detail, loses to the plane that is actually sharp.
    private static func detail(_ image: CGImage) -> Detail? {
        let width = 480
        let height = max(64, Int((Double(image.height) * Double(width) / Double(max(image.width, 1))).rounded()))
        var px = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &px, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        var luma = [Double](repeating: 0, count: width * height)
        for i in luma.indices {
            let o = i * 4
            luma[i] = Double(px[o]) * 0.3 + Double(px[o + 1]) * 0.59 + Double(px[o + 2]) * 0.11
        }
        let soft = gaussian(luma, width: width, height: height, sigma: 2.2)
        var cells = [Double](repeating: 0, count: cols * rows)
        for row in 0..<rows {
            for col in 0..<cols {
                let x0 = col * width / cols
                let x1 = (col + 1) * width / cols
                let y0 = row * height / rows
                let y1 = (row + 1) * height / rows
                var acc = 0.0
                var n = 0
                for y in stride(from: y0, to: y1, by: 2) {
                    for x in stride(from: x0, to: x1, by: 2) {
                        let i = y * width + x
                        acc += abs(luma[i] - soft[i])
                        n += 1
                    }
                }
                cells[row * cols + col] = n > 0 ? acc / Double(n) : 0
            }
        }
        return Detail(cells: cells, cols: cols, rows: rows)
    }

    private static func cluster(_ map: Detail) -> (box: CGRect, score: Double)? {
        var best = 0.0
        var peak = 0
        for (i, value) in map.cells.enumerated() where value > best {
            best = value
            peak = i
        }
        guard best > 0.4 else { return nil }
        let peakCol = peak % map.cols
        let peakRow = peak / map.cols
        let gate = best * 0.72
        var minC = peakCol
        var maxC = peakCol
        var minR = peakRow
        var maxR = peakRow
        var stack = [peak]
        var seen = Set<Int>()
        while let i = stack.popLast() {
            if seen.contains(i) { continue }
            seen.insert(i)
            if map.cells[i] < gate { continue }
            let col = i % map.cols
            let row = i / map.cols
            if max(abs(col - peakCol), abs(row - peakRow)) > 2 { continue }
            minC = min(minC, col)
            maxC = max(maxC, col)
            minR = min(minR, row)
            maxR = max(maxR, row)
            for next in [i - 1, i + 1, i - map.cols, i + map.cols] where next >= 0 && next < map.cells.count {
                let nextCol = next % map.cols
                if abs(nextCol - col) > 1 { continue }
                stack.append(next)
            }
        }
        while maxC - minC + 1 < 3 {
            if minC > 0, peakCol - minC <= maxC - peakCol { minC -= 1 }
            else if maxC + 1 < map.cols { maxC += 1 }
            else if minC > 0 { minC -= 1 }
            else { break }
        }
        while maxR - minR + 1 < 2 {
            if minR > 0, peakRow - minR <= maxR - peakRow { minR -= 1 }
            else if maxR + 1 < map.rows { maxR += 1 }
            else if minR > 0 { minR -= 1 }
            else { break }
        }
        let box = CGRect(
            x: CGFloat(minC) / CGFloat(map.cols),
            y: CGFloat(minR) / CGFloat(map.rows),
            width: CGFloat(maxC - minC + 1) / CGFloat(map.cols),
            height: CGFloat(maxR - minR + 1) / CGFloat(map.rows)
        )
        return (box, mean(map, unit: box))
    }

    private static func mean(_ map: Detail, unit: CGRect) -> Double {
        var acc = 0.0
        var n = 0
        for row in 0..<map.rows {
            for col in 0..<map.cols {
                let cx = (CGFloat(col) + 0.5) / CGFloat(map.cols)
                let cy = (CGFloat(row) + 0.5) / CGFloat(map.rows)
                guard unit.contains(CGPoint(x: cx, y: cy)) else { continue }
                acc += map.cells[row * map.cols + col]
                n += 1
            }
        }
        if n == 0, !map.cells.isEmpty {
            let col = min(map.cols - 1, max(0, Int(unit.midX * CGFloat(map.cols))))
            let row = min(map.rows - 1, max(0, Int(unit.midY * CGFloat(map.rows))))
            return map.cells[row * map.cols + col]
        }
        return n > 0 ? acc / Double(n) : 0
    }

    private static func gaussian(_ src: [Double], width: Int, height: Int, sigma: Double) -> [Double] {
        let radius = max(1, Int((sigma * 2.5).rounded()))
        var kernel = [Double](repeating: 0, count: radius * 2 + 1)
        var weight = 0.0
        for i in -radius...radius {
            let v = exp(-0.5 * Double(i * i) / (sigma * sigma))
            kernel[i + radius] = v
            weight += v
        }
        for i in kernel.indices { kernel[i] /= weight }
        var horizontal = [Double](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in -radius...radius {
                    let xx = min(width - 1, max(0, x + k))
                    acc += src[y * width + xx] * kernel[k + radius]
                }
                horizontal[y * width + x] = acc
            }
        }
        var dst = [Double](repeating: 0, count: src.count)
        for y in 0..<height {
            for x in 0..<width {
                var acc = 0.0
                for k in -radius...radius {
                    let yy = min(height - 1, max(0, y + k))
                    acc += horizontal[yy * width + x] * kernel[k + radius]
                }
                dst[y * width + x] = acc
            }
        }
        return dst
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
