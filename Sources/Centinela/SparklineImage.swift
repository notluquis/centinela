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
            let path = NSBezierPath()
            path.lineWidth = 1.2
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // One pixel of margin top and bottom: at width 1.2 the maximum and the minimum would
            // otherwise be clipped by the edge of the image.
            let margin: CGFloat = 1
            for (index, point) in points.enumerated() {
                let spot = NSPoint(x: point.x * width, y: margin + point.y * (height - margin * 2))
                if index == 0 { path.move(to: spot) } else { path.line(to: spot) }
            }
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
