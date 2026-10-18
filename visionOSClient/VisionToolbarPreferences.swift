import SwiftUI

/// All activation stays in the system hover compositor. No gaze position or hover state enters
/// application state, and revealing the toolbar never changes the stream's measured viewport.
struct VisionToolbarReveal: ViewModifier {
    let automatic: Bool
    let reduceMotion: Bool
    let group: HoverEffectGroup
    func body(content: Content) -> some View {
        content
            // Describe the hover participant itself before applying its compositor effect.
            // A zero-size clip removes the bar's visual region; a separate clear view with an
            // interaction shape did not restore gaze activation on build 22 hardware.
            .contentShape(.hoverEffect, Rectangle())
            .hoverEffect(in: group) { effect, active, _ in
                effect.animation(reduceMotion ? nil : .easeInOut(duration: 0.18).delay(active ? 0.35 : 1.0)) {
                    $0.opacity(!automatic || active ? 1 : 0)
                }
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
