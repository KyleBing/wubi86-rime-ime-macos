import AppKit

/// 码表助手词条操作图标（viewBox 10×10），做成模板图以便跟随明暗颜色。
enum DictEditorIcons {
    static let up = image(paths: [
        "M5.89,1.17,9.28,7.93a1,1,0,0,1-.45,1.35,1,1,0,0,1-.45.1H1.62a1,1,0,0,1-1-1,1,1,0,0,1,.1-.45L4.11,1.17a1,1,0,0,1,1.78,0Z"
    ])
    static let down = image(paths: [
        "M5.89,8.83,9.28,2.07A1,1,0,0,0,8.83.72a1,1,0,0,0-.45-.1H1.62a1,1,0,0,0-1,1,1,1,0,0,0,.1.45L4.11,8.83a1,1,0,0,0,1.78,0Z"
    ])
    static let upAlt = image(paths: [
        "M7.81,5,5.89,1.17a1,1,0,0,0-1.78,0L2.19,5Z",
        "M8.57,6.53H1.43L.72,7.93a1,1,0,0,0-.1.45,1,1,0,0,0,1,1H8.38a1,1,0,0,0,.45-.1,1,1,0,0,0,.45-1.35Z"
    ])
    static let downAlt = image(paths: [
        "M1.57,3.76H8.43l.85-1.69A1,1,0,0,0,8.83.72a1,1,0,0,0-.45-.1H1.62a1,1,0,0,0-1,1,1,1,0,0,0,.1.45Z",
        "M2.34,5.29,4.11,8.83a1,1,0,0,0,1.78,0L7.66,5.29Z"
    ])
    static let edit = image(paths: [
        "M9.61.39a1.3,1.3,0,0,0-1.86,0L1.27,6.86,1.18,7,.63,8.42,0,10l1.58-.62L3,8.83l.16-.1L9.61,2.25A1.3,1.3,0,0,0,9.61.39Z"
    ])
    static let delete = image(draw: { _ in
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        path.move(to: CGPoint(x: 1.2, y: 1.2))
        path.line(to: CGPoint(x: 8.8, y: 8.8))
        path.move(to: CGPoint(x: 8.8, y: 1.2))
        path.line(to: CGPoint(x: 1.2, y: 8.8))
        NSColor.black.setStroke()
        path.stroke()
    })

    private static func image(paths: [String]) -> NSImage {
        image { _ in
            NSColor.black.setFill()
            for d in paths {
                SVGPath(d: d).bezierPath().fill()
            }
        }
    }

    private static func image(draw: @escaping (NSRect) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: 10, height: 10), flipped: true, drawingHandler: { rect in
            draw(rect)
            return true
        })
        image.isTemplate = true
        return image
    }
}

/// 只覆盖码表助手这几枚图标用到的路径命令。
private struct SVGPath {
    let d: String

    func bezierPath() -> NSBezierPath {
        let path = NSBezierPath()
        var i = d.startIndex
        var command: Character = "M"
        var current = CGPoint.zero
        var start = CGPoint.zero

        func skip() {
            while i < d.endIndex, d[i] == "," || d[i].isWhitespace { i = d.index(after: i) }
        }

        func readNumber() -> CGFloat? {
            skip()
            guard i < d.endIndex else { return nil }
            let sign = d[i]
            if sign.isLetter { return nil }
            var j = i
            if d[j] == "+" || d[j] == "-" { j = d.index(after: j) }
            var sawDigit = false
            var sawDot = false
            while j < d.endIndex {
                if d[j].isNumber {
                    sawDigit = true
                    j = d.index(after: j)
                } else if d[j] == ".", !sawDot {
                    sawDot = true
                    j = d.index(after: j)
                } else {
                    break
                }
            }
            guard sawDigit, let value = Double(d[i..<j]) else { return nil }
            i = j
            return CGFloat(value)
        }

        while i < d.endIndex {
            skip()
            guard i < d.endIndex else { break }
            if d[i].isLetter {
                command = d[i]
                i = d.index(after: i)
                if command == "Z" || command == "z" {
                    path.close()
                    current = start
                    continue
                }
            }
            switch command {
            case "M", "m":
                guard let x = readNumber(), let y = readNumber() else { return path }
                current = command == "m" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                start = current
                path.move(to: current)
                command = command == "m" ? "l" : "L"
            case "L", "l":
                guard let x = readNumber(), let y = readNumber() else { return path }
                current = command == "l" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                path.line(to: current)
            case "H", "h":
                guard let x = readNumber() else { return path }
                current.x = command == "h" ? current.x + x : x
                path.line(to: current)
            case "V", "v":
                guard let y = readNumber() else { return path }
                current.y = command == "v" ? current.y + y : y
                path.line(to: current)
            case "A", "a":
                guard let rx = readNumber(), let ry = readNumber(),
                      let rotation = readNumber(),
                      let large = readNumber(), let sweep = readNumber(),
                      let x = readNumber(), let y = readNumber() else { return path }
                let end = command == "a" ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                addArc(path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, large: large != 0, sweep: sweep != 0)
                current = end
            default:
                return path
            }
        }
        return path
    }

    // SVG 椭圆弧转成三次贝塞尔，坐标系与 viewBox 一致（y 向下）。
    private func addArc(
        _ path: NSBezierPath,
        from start: CGPoint,
        to end: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        rotation: CGFloat,
        large: Bool,
        sweep: Bool
    ) {
        var rx = abs(rx)
        var ry = abs(ry)
        if rx < 0.001 || ry < 0.001 {
            path.line(to: end)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)
        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        var rxsq = rx * rx
        var rysq = ry * ry
        let lambda = x1p * x1p / rxsq + y1p * y1p / rysq
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
            rxsq = rx * rx
            rysq = ry * ry
        }
        let den = rxsq * y1p * y1p + rysq * x1p * x1p
        var coef = sqrt(max(0, (rxsq * rysq - rxsq * y1p * y1p - rysq * x1p * x1p) / max(den, 0.000_001)))
        if large == sweep { coef = -coef }
        let cxp = coef * rx * y1p / ry
        let cyp = coef * -ry * x1p / rx
        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            var angle = acos(min(1, max(-1, dot / max(len, 0.000_001))))
            if ux * vy - uy * vx < 0 { angle = -angle }
            return angle
        }

        let theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = vectorAngle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let step = delta / CGFloat(segments)
        for index in 0..<segments {
            let t1 = theta1 + step * CGFloat(index)
            let t2 = t1 + step
            let alpha = sin(step) * (sqrt(4 + 3 * pow(tan(step / 2), 2)) - 1) / 3
            func point(_ t: CGFloat) -> CGPoint {
                CGPoint(
                    x: cx + cosPhi * rx * cos(t) - sinPhi * ry * sin(t),
                    y: cy + sinPhi * rx * cos(t) + cosPhi * ry * sin(t)
                )
            }
            func derivative(_ t: CGFloat) -> CGPoint {
                CGPoint(
                    x: -cosPhi * rx * sin(t) - sinPhi * ry * cos(t),
                    y: -sinPhi * rx * sin(t) + cosPhi * ry * cos(t)
                )
            }
            let p1 = point(t1)
            let p2 = point(t2)
            let d1 = derivative(t1)
            let d2 = derivative(t2)
            path.curve(
                to: p2,
                controlPoint1: CGPoint(x: p1.x + alpha * d1.x, y: p1.y + alpha * d1.y),
                controlPoint2: CGPoint(x: p2.x - alpha * d2.x, y: p2.y - alpha * d2.y)
            )
        }
    }
}
