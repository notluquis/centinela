import CentinelaCore
import SwiftUI

struct MenuBarLabel: View {
    let state: AppState

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: symbol)
            // Gated on `isConfigured` and not just on the count being zero. The count is zero
            // once the session is forgotten, but the bar must not be able to show a number that
            // belongs to nobody even if some future path leaves data behind.
            if watching, state.badgeValue > 0 {
                // A trailing "+" when the count hit its fetch limit, so the bar says "15+" instead
                // of a "15" that a busy org would read as the whole story.
                Text(state.badgeAtCap ? "\(state.badgeValue)+" : state.badgeValue.formatted())
                    // Same rolling digits as the panel header. Whether the menu bar honours it is
                    // not something this project has measured: the bar is drawn by the system and
                    // the one thing already measured about it is that only `Text` and `Image`
                    // render there reliably. If it does nothing, it degrades to the plain swap
                    // that was there before.
                    .contentTransition(.numericText(value: Double(state.badgeValue)))
                    .panelMotion(state.badgeValue)
            }
            // As an image rather than a live `Path`: a `MenuBarExtra` label is drawn by the
            // system, and up there `Text` and `Image` are the only things that render
            // reliably. A vector shape showed up in the panel and NOT in the bar, which is
            // exactly where it was wanted.
            if watching, let sparkline = Sparkline.image(state.data.series.points.map(\.count)) {
                Image(nsImage: sparkline)
            }
        }
        .accessibilityLabel(accessibleDescription)
        // No fixed colour: in the macOS 26 and 27 menu bar the background is transparent with
        // the wallpaper behind it, so a colour of our own stops contrasting depending on the
        // desktop. A template symbol is resolved by the system, which knows whether things are
        // light or dark. Only an outage is painted red, the one state that justifies breaking
        // the rule.
        .foregroundStyle(tint)
    }

    /// Whether there is a session to report on at all. Same condition the panel uses to decide
    /// between its contents and "Not configured yet", so the two cannot disagree.
    private var watching: Bool { state.settings.isConfigured }

    private var symbol: String {
        // A seal with a tick says "everything is fine", and with no session nothing is known to
        // be fine: it was reporting on an account the app no longer reaches. A crossed-out eye
        // says the app is not looking, which is the true state and not an alarm.
        guard watching else { return "eye.slash" }
        if state.hasOutage { return "bolt.horizontal.circle.fill" }
        return state.badgeValue > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal"
    }

    private var tint: AnyShapeStyle {
        // Signed out was drawn in `.secondary` and it washed out: the menu bar background is the
        // wallpaper, so a dimmed glyph loses its contrast against a light desktop and reads as a
        // rendering fault rather than a state. The crossed-out eye already carries the meaning.
        state.hasOutage ? AnyShapeStyle(.red) : AnyShapeStyle(.primary)
    }

    private var accessibleDescription: String {
        guard watching else { return "Not signed in. Centinela is not watching anything." }
        var parts = [Sparkline.summary(state.data.series.points.map(\.count), window: state.settings.window)]
        if state.hasOutage { parts.insert("A service is down.", at: 0) }
        return parts.joined(separator: " ")
    }
}

/// Draws the sparkline inside the panel. The arithmetic lives in `Sparkline.normalize`, which
/// does have tests; this only traces the points it returns.
///
/// Line plus a gradient area beneath it plus a dot on the latest value — the shape of a
/// change-over-time chart the way Sentry's own dashboard and the menu-bar meters (Stats, iStat)
/// draw one, instead of a bare polyline. The segments stay straight: these are error spikes, and
/// a smoothed curve would round a real spike into a swell it never was.
///
/// Scrub-to-read: the pointer over the chart marks the bucket under it and names its count and
/// time, the way Stats reveals a value on hover. It is a bonus and never required — the headline
/// count above says the total without any interaction (HIG: "don't require interaction to reveal
/// critical information").
struct SparklinePath: View {
    let points: [EventSeries.Point]
    @State private var hovered: Int?

    var body: some View {
        GeometryReader { geo in
            let plotted = Sparkline.normalize(points.map(\.count)).map { point in
                // `y` comes with 0 at the bottom; in Core Graphics 0 is the top. One point of
                // inset top and bottom so the peak and the dot are not clipped by the frame.
                CGPoint(
                    x: point.x * geo.size.width,
                    y: 1 + (1 - point.y) * (geo.size.height - 2)
                )
            }
            ZStack(alignment: .topLeading) {
                if plotted.count > 1 {
                    area(plotted, height: geo.size.height)
                        .fill(LinearGradient(
                            colors: [Color.accentColor.opacity(0.28), Color.accentColor.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    line(plotted)
                        .stroke(Color.accentColor, style: StrokeStyle(
                            lineWidth: 1.5, lineCap: .round, lineJoin: .round
                        ))
                    marker(plotted, height: geo.size.height)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    guard plotted.count > 1, geo.size.width > 0 else { return }
                    let ratio = max(0, min(1, location.x / geo.size.width))
                    hovered = Int((ratio * CGFloat(plotted.count - 1)).rounded())
                case .ended:
                    hovered = nil
                }
            }
        }
        .accessibilityHidden(true)
    }

    /// Either the resting dot on the latest bucket, or — while scrubbing — a crosshair, a dot on
    /// the hovered bucket, and a label naming its count and time.
    @ViewBuilder private func marker(_ plotted: [CGPoint], height: CGFloat) -> some View {
        if let index = hovered, plotted.indices.contains(index), points.indices.contains(index) {
            let spot = plotted[index]
            let point = points[index]
            let when = point.time.formatted(.dateTime.month().day().hour().minute())
            Rectangle()
                .fill(Color.accentColor.opacity(0.35))
                .frame(width: 1, height: height)
                .position(x: spot.x, y: height / 2)
            Circle()
                .fill(Color.accentColor)
                .frame(width: 5, height: 5)
                .position(spot)
            // Pinned top-leading rather than floating at the point: the chart is only 40 pt tall,
            // and a label chasing the pointer would clip against the count above and the frame
            // edges. A material chip in the corner stays readable wherever the pointer is.
            Text("^[\(point.count) error](inflect: true) · \(when)")
                .font(.caption2)
                .foregroundStyle(.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 5))
                .fixedSize()
                .padding(.leading, 2)
        } else if let last = plotted.last {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 4, height: 4)
                .position(last)
        }
    }

    private func line(_ plotted: [CGPoint]) -> Path {
        Path { path in
            path.addLines(plotted)
        }
    }

    /// The line closed down to the baseline and back, so the fill sits under the curve.
    private func area(_ plotted: [CGPoint], height: CGFloat) -> Path {
        Path { path in
            path.addLines(plotted)
            path.addLine(to: CGPoint(x: plotted[plotted.count - 1].x, y: height))
            path.addLine(to: CGPoint(x: plotted[0].x, y: height))
            path.closeSubpath()
        }
    }
}
