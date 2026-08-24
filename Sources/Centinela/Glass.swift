import SwiftUI

/// Liquid Glass, the material macOS 26 introduced, only where it helps and only where it exists.
///
/// Two decisions worth writing down, both straight from Apple's "Adopting Liquid Glass" guide:
///
/// 1. **The panel background is left alone.** `MenuBarExtra(.window)` already draws it with the
///    system material, and the guide says to "audit the backgrounds of sheets and popovers […]
///    remove those custom background views". Stacking a second material on top looks murky, not
///    glassy.
/// 2. **The footer controls do get it.** They are loose buttons over that material, which is
///    exactly the case `.buttonStyle(.glass)` exists for. The same guide says to use the button
///    style APIs "instead of creating buttons with custom Liquid Glass effects".
///
/// The deployment target is macOS 14, so everything sits behind `#available`: on 14 and 15 it
/// falls back to the plain style, which is the correct one there.
extension View {
    func glassButton() -> some View {
        modifier(GlassButton())
    }
}

/// Glass is a transparent material, and "Reduce transparency" is the system switch for people who
/// cannot read text over one. Honouring it is not optional decoration: with it on, the footer
/// controls fall back to the plain style, which is what that setting is asking for.
///
/// Neither of the two repositories this project is modelled on handles it. Measured across both
/// checkouts: zero files mention `accessibilityReduceTransparency`.
private struct GlassButton: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.plain)
        }
    }
}

/// Groups several glass elements into a single layer.
///
/// Apple's guide is blunt about it: if you apply glass effects to your own elements, combine
/// them in a `GlassEffectContainer`, "which helps optimize performance while fluidly morphing
/// Liquid Glass shapes into each other". Three loose buttons open three layers.
///
/// On macOS 14 and 15 the container does not exist and this is a plain `HStack`, which is right
/// there.
struct GlassGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) { content }
            }
        } else {
            HStack(spacing: 6) { content }
        }
    }
}
