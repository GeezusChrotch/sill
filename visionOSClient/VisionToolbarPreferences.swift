import SwiftUI

/// All activation stays in the system hover compositor. No gaze position or hover state enters
/// application state, and revealing the toolbar never changes the stream's measured viewport.
struct VisionToolbarReveal: ViewModifier {
    let automatic: Bool
    let reduceMotion: Bool
    let group: HoverEffectGroup
    func body(content: Content) -> some View {
        content
            // Keep the bar's compositor fade separate from its visible glance target.
            .contentShape(.hoverEffect, Rectangle())
            .hoverEffect(in: group) { effect, active, _ in
                effect.animation(.easeInOut(duration: reduceMotion ? 0 : 0.18).delay(active ? 0.65 : 1.0)) {
                    $0.opacity(!automatic || active ? 1 : 0)
                }
            }
    }
}

/// A translucent surface remains visible while Auto is collapsed. It shares
/// the bars' hover group and stays centered behind each toolbar, rather than on a rail
/// between the picture and toolbar. It is a glance target, with no tap action to compete
/// with the controls above it in the ornament's hit-test hierarchy.
struct VisionToolbarGlanceTarget: View {
    let vertical: Bool
    let length: CGFloat
    let reduceMotion: Bool
    let group: HoverEffectGroup

    var body: some View {
        Capsule()
            .fill(.black.opacity(0.50))
            .frame(width: vertical ? 24 : length, height: vertical ? length : 24)
            .contentShape(.hoverEffect, Capsule())
            .hoverEffect(.highlight, in: group)
            .hoverEffect(in: group) { effect, active, _ in
                effect.animation(.easeInOut(duration: reduceMotion ? 0 : 0.18).delay(active ? 0.65 : 1.0)) {
                    $0.opacity(active ? 0 : 1)
                }
            }
            .accessibilityHidden(true)
    }
}

/// On visionOS 26+, looking back at the picture preserves an already revealed
/// group but cannot reveal an inactive group. Real remote input changes the
/// scene-local group identity to begin a fresh, inactive phase.
struct VisionToolbarPreserve: ViewModifier {
    let group: HoverEffectGroup
    func body(content: Content) -> some View {
        if #available(visionOS 26.0, *) {
            content
                .contentShape(Rectangle())
                .hoverEffect(in: group.behavior(.preservesGroup)) { effect, _, _ in effect }
        } else {
            content
        }
    }
}
