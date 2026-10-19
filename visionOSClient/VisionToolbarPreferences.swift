import SwiftUI

/// The system owns hover presentation and its interaction regions. Expanded controls live in a
/// hover-presented ornament, never in a permanently mounted opacity-hidden full-size toolbar.
/// The presenting surface follows the group: only the compact pills may activate it.
struct VisionToolbarPresentation<Controls: View>: ViewModifier {
    let automatic: Bool
    let group: HoverEffectGroup
    let anchor: UnitPoint
    let alignment: Alignment3D
    @ViewBuilder var controls: () -> Controls

    func body(content: Content) -> some View {
        if #available(visionOS 26.0, *), automatic {
            content.hoverEffect(
                .ornament(attachmentAnchor: .scene(anchor), contentAlignment: alignment) {
                    controls()
                        .hoverEffectGroup(group.behavior(.preservesGroup))
                } effect: { effect, active, _ in
                    // Zero-size during dwell, not transparent full-size buttons. The native
                    // ornament also withdraws its controls when its effect is inactive.
                    effect.animation(.linear(duration: 0).delay(active ? 0.65 : 0)) {
                        $0.scaleEffect(active ? 1 : 0).opacity(active ? 1 : 0)
                    }
                }, in: group.behavior(.followsGroup))
        } else {
            content
        }
    }
}

/// A real compact interaction shape. Tapping offers an accessible explicit reveal and is also
/// the visionOS 2–25 fallback, where native hover ornament presentation is unavailable.
struct VisionToolbarGlanceTarget: View {
    let vertical: Bool
    let length: CGFloat
    let reduceMotion: Bool
    let group: HoverEffectGroup
    var reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            Capsule()
                .fill(.black.opacity(0.50))
                .frame(width: vertical ? 24 : length, height: vertical ? length : 24)
                .contentShape(.interaction, Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(.interaction, Capsule())
        .hoverEffect(.highlight, in: group)
        .accessibilityLabel("Show toolbars")
        .modifier(VisionToolbarPillFade(group: group))
    }
}

private struct VisionToolbarPillFade: ViewModifier {
    let group: HoverEffectGroup
    func body(content: Content) -> some View {
        if #available(visionOS 26.0, *) {
            content.hoverEffect(in: group.behavior(.followsGroup)) { effect, active, _ in
                effect.animation(.linear(duration: 0).delay(active ? 0.65 : 0)) {
                    $0.opacity(active ? 0 : 1)
                }
            }
        } else { content }
    }
}

/// Looking back at the picture preserves a revealed group without revealing an inactive one.
/// Real remote input changes its scene-local identity to begin a fresh inactive phase.
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
