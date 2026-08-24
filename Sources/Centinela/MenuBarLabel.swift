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
            if watching, state.totalErrors > 0 {
                Text(state.totalErrors, format: .number)
                    // Same rolling digits as the panel header. Whether the menu bar honours it is
                    // not something this project has measured: the bar is drawn by the system and
                    // the one thing already measured about it is that only `Text` and `Image`
                    // render there reliably. If it does nothing, it degrades to the plain swap
                    // that was there before.
                    .contentTransition(.numericText(value: Double(state.totalErrors)))
                    .panelMotion(state.totalErrors)
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
        return state.totalErrors > 0 ? "exclamationmark.triangle.fill" : "checkmark.seal"
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
/// does have tests.
struct SparklinePath: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geo in
            Path { path in
                let points = Sparkline.normalize(values)
                guard points.count > 1 else { return }
                for (index, point) in points.enumerated() {
                    // `y` comes with 0 at the bottom; in Core Graphics 0 is the top.
                    let spot = CGPoint(x: point.x * geo.size.width, y: (1 - point.y) * geo.size.height)
                    if index == 0 { path.move(to: spot) } else { path.addLine(to: spot) }
                }
            }
            .stroke(style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
