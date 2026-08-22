import Foundation

/// The sparkline that sits next to the count, up in the menu bar.
///
/// Only the arithmetic lives here (normalizing a series to points between 0 and 1) because that
/// is the only part that can be wrong in a way you cannot see. The drawing lives in the app
/// target, where there is nothing to test.
public enum Sparkline {
    /// Normalizes to `0...1` coordinates, with `y = 0` at the bottom.
    ///
    /// Three cases a naive `map` ruins:
    /// - empty series → no points, not a division by zero;
    /// - a single point → there is no width to spread over, so it is anchored at the centre;
    /// - a flat series (every value the same, all zeros included) → a line down the middle, not
    ///   at the top or the bottom. `max - min` is 0 and dividing by that yields `NaN`, which
    ///   Core Graphics does not raise: it draws nothing, and the widget looks like it has no
    ///   data exactly when it does.
    public static func normalize(_ values: [Int]) -> [(x: Double, y: Double)] {
        guard !values.isEmpty else { return [] }
        guard values.count > 1 else { return [(x: 0.5, y: 0.5)] }

        let maximum = values.max() ?? 0
        let minimum = values.min() ?? 0
        let range = Double(maximum - minimum)
        let lastIndex = Double(values.count - 1)

        return values.enumerated().map { index, value in
            let x = Double(index) / lastIndex
            let y = range > 0 ? Double(value - minimum) / range : 0.5
            return (x: x, y: y)
        }
    }

    /// Sums up the series into a short sentence, for the tooltip and for VoiceOver.
    public static func summary(_ values: [Int], window: TimeWindow) -> String {
        let total = values.reduce(0, +)
        guard total > 0 else { return "No errors in the last \(window.label)." }
        let peak = values.max() ?? 0
        return "\(total) errors in the last \(window.label), peaking at \(peak) per interval."
    }
}
