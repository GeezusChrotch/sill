import SwiftUI

private struct VisionToolbarPositionKey: EnvironmentKey {
    static let defaultValue: Binding<String>? = nil
}

extension EnvironmentValues {
    var visionToolbarPosition: Binding<String>? {
        get { self[VisionToolbarPositionKey.self] }
        set { self[VisionToolbarPositionKey.self] = newValue }
    }
}

private struct VisionToolbarAutomaticKey: EnvironmentKey {
    static let defaultValue: Binding<Bool>? = nil
}

extension EnvironmentValues {
    var visionToolbarAutomatic: Binding<Bool>? {
        get { self[VisionToolbarAutomaticKey.self] }
        set { self[VisionToolbarAutomaticKey.self] = newValue }
    }
}

/// All activation stays in the system hover compositor. No gaze position or hover state enters
/// application state, and revealing the toolbar never changes the stream's measured viewport.
struct VisionToolbarReveal: ViewModifier {
    let automatic: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content.hoverEffect { effect, active, proxy in
            effect.animation(reduceMotion ? nil : .easeInOut(duration: 0.18).delay(active ? 0.45 : 0.15)) {
                $0.clipShape(VisionToolbarRevealShape(size: !automatic || active ? proxy.size : .zero))
            }
        }
    }
}

private struct VisionToolbarRevealShape: Shape {
    var size: CGSize
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(size.width, size.height) }
        set { size = CGSize(width: newValue.first, height: newValue.second) }
    }

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.maxX - size.width, y: rect.minY, width: size.width, height: size.height))
    }
}
