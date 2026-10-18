import SwiftUI

/// All activation stays in the system hover compositor. No gaze position or hover state enters
/// application state, and revealing the toolbar never changes the stream's measured viewport.
struct VisionToolbarReveal: ViewModifier {
    let automatic: Bool
    let reduceMotion: Bool
    let group: HoverEffectGroup
    var anchor: UnitPoint = .topTrailing

    func body(content: Content) -> some View {
        content.hoverEffect(in: group) { effect, active, proxy in
            effect.animation(reduceMotion ? nil : .easeInOut(duration: 0.18).delay(active ? 0.35 : 1.0)) {
                $0.clipShape(VisionToolbarRevealShape(size: !automatic || active ? proxy.size : .zero, anchor: anchor))
            }
        }
    }
}

private struct VisionToolbarRevealShape: Shape {
    var size: CGSize
    let anchor: UnitPoint
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX + (rect.width - size.width) * anchor.x,
                    y: rect.minY + (rect.height - size.height) * anchor.y,
                    width: size.width, height: size.height))
    }
}

/// The reveal clip belongs only to the visible bar. This non-actionable background
/// remains at that bar's exact layout bounds even when its visual content is clipped.
/// System hover activates the shared group without exposing gaze state to app code.
struct VisionToolbarRevealTarget: ViewModifier {
    let group: HoverEffectGroup

    func body(content: Content) -> some View {
        content.background {
            Rectangle()
                .fill(.clear)
                .contentShape(.interaction, Rectangle())
                .hoverEffect(in: group) { effect, _, _ in effect }
                .accessibilityHidden(true)
        }
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
