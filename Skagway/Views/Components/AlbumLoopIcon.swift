import SwiftUI

/// Outline of two semi-circular arrows chasing each other. Used for Loop Album in the header.
struct AlbumLoopIcon: View {
    var body: some View {
        // Size to the same slot as neighboring SF Symbols (shuffle, play).
        ZStack {
            Image(systemName: "circle")
                .opacity(0)
            Canvas { context, size in
                let inset = max(1.1, min(size.width, size.height) * 0.08)
                let rect = CGRect(origin: .zero, size: size).insetBy(dx: inset, dy: inset)
                let radius = min(rect.width, rect.height) / 2
                let center = CGPoint(x: rect.midX, y: rect.midY)
                let lineWidth = max(1.25, radius * 0.26)

                var strokes = Path()
                var heads = Path()
                addChasingArrow(
                    strokes: &strokes,
                    heads: &heads,
                    center: center,
                    radius: radius,
                    startDegrees: -32,
                    endDegrees: 122
                )
                addChasingArrow(
                    strokes: &strokes,
                    heads: &heads,
                    center: center,
                    radius: radius,
                    startDegrees: 148,
                    endDegrees: 302
                )

                context.stroke(
                    strokes,
                    with: .foreground,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                context.fill(heads, with: .foreground)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Clockwise arc plus a triangular arrowhead at the tip.
private func addChasingArrow(
    strokes: inout Path,
    heads: inout Path,
    center: CGPoint,
    radius: CGFloat,
    startDegrees: Double,
    endDegrees: Double
) {
    let headSweep: Double = 18
    let arcEnd = endDegrees - headSweep
    strokes.addArc(
        center: center,
        radius: radius,
        startAngle: .degrees(startDegrees),
        endAngle: .degrees(arcEnd),
        clockwise: true
    )

    let tipAngle = Angle.degrees(endDegrees).radians
    let baseAngle = Angle.degrees(arcEnd).radians
    let tip = CGPoint(
        x: center.x + radius * CGFloat(cos(tipAngle)),
        y: center.y + radius * CGFloat(sin(tipAngle))
    )
    let base = CGPoint(
        x: center.x + radius * CGFloat(cos(baseAngle)),
        y: center.y + radius * CGFloat(sin(baseAngle))
    )
    let outward = CGPoint(x: CGFloat(cos(baseAngle)), y: CGFloat(sin(baseAngle)))
    let halfWidth = radius * 0.36
    let left = CGPoint(x: base.x + outward.x * halfWidth, y: base.y + outward.y * halfWidth)
    let right = CGPoint(x: base.x - outward.x * halfWidth, y: base.y - outward.y * halfWidth)

    heads.move(to: left)
    heads.addLine(to: tip)
    heads.addLine(to: right)
    heads.closeSubpath()
}
