import SwiftUI

/// One curve and one switch for the whole app.
///
/// It exists because of what the audit of the two reference repositories showed: TheBoringNotch
/// animates in 130 places with `.easeInOut`, `.spring`, `.smooth`, `.bouncy` and
/// `.interactiveSpring` scattered through the views and no shared definition, so nothing moves
/// quite like anything else. Stats animates once in forty-three thousand lines. Neither is the
/// thing to copy: the first has no vocabulary, the second has no motion.
///
/// **And neither honours reduce motion.** Measured across both checkouts: TheBoringNotch has zero
/// files mentioning it, Stats has one. "Reduce motion" is a real switch in System Settings that
/// people turn on because animation makes them ill, and a menu bar app that ignores it animates
/// in the corner of their eye all day.
enum Motion {
    /// Fast enough that nobody waits for it, slow enough to read as a change rather than a jump.
    /// `.smooth` and not a spring: nothing here is being dragged, and overshoot on a number that
    /// counts errors reads as a glitch.
    static let curve: Animation = .smooth(duration: 0.22)
}

extension View {
    /// Animates `value` with the app's one curve, and with none at all when the person asked the
    /// system for none.
    func panelMotion<V: Equatable>(_ value: V) -> some View {
        modifier(PanelMotion(value: value))
    }
}

private struct PanelMotion<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : Motion.curve, value: value)
    }
}
