import AppKit
import CentinelaCore

// The drawing lives here and not next to the arithmetic on purpose: `CentinelaCore` does not
// import AppKit, and that is why its suite runs on a CI runner with no graphics session.
// `Sparkline.normalize` has tests; this is only tracing the points it returns.
extension Sparkline {
    /// Draws the sparkline as a template image, for the menu bar label.
    ///
    /// Template on purpose (`isTemplate`): in the macOS 26 and 27 menu bar the background is
    /// transparent with the wallpaper behind it, so the colour has to be the system's call — it
    /// is the one that knows whether things are light or dark. A colour of our own stops
    /// contrasting depending on each person's desktop.
    static func image(_ values: [Int], width: CGFloat = 26, height: CGFloat = 11) -> NSImage? {
        let points = normalize(values)
        guard points.count > 1 else { return nil }

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // One pixel of margin top and bottom: at width 1.2 the maximum and the minimum would
            // otherwise be clipped by the edge of the image.
            let margin: CGFloat = 1
            func spot(_ point: (x: Double, y: Double)) -> NSPoint {
                NSPoint(x: point.x * width, y: margin + point.y * (height - margin * 2))
            }

            let line = NSBezierPath()
            line.lineWidth = 1.2
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            for (index, point) in points.enumerated() {
                if index == 0 { line.move(to: spot(point)) } else { line.line(to: spot(point)) }
            }

            // A gradient fill under the line, the same shape the panel's sparkline has, so the two
            // read as one chart at two sizes. The image is a template — only the ALPHA is kept and
            // the system tints the rest — so the ramp is alpha, strongest at the peak and fading to
            // nothing at the baseline. No end dot up here: at 26×11 it clips against the right edge
            // and reads as a blob, and the fill alone carries the upgrade.
            let area = line.copy() as? NSBezierPath ?? NSBezierPath()
            area.line(to: NSPoint(x: width, y: 0))
            area.line(to: NSPoint(x: 0, y: 0))
            area.close()
            NSGradient(colors: [
                NSColor.black.withAlphaComponent(0.40),
                NSColor.black.withAlphaComponent(0.0)
            ])?.draw(in: area, angle: -90)

            NSColor.black.setStroke()
            line.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
