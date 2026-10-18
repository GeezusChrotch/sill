import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import StreamProtocol

/// Attaches hardware-only recognizers to the actual video view, without placing a UIKit hit-test
/// overlay in front of visionOS gaze/pinch gestures. Put this representable in a background.
struct VisionHardwarePointer: UIViewRepresentable {
    var displayView: UIView
    var videoSize: CGSize
    var enabled: Bool
    var source: StreamSource
    var momentum: VisionScrollMomentum
    var send: (InputEvent) -> Void
    var pointerBegan: () -> Void = {}
    var pointerEnded: () -> Void = {}

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let anchor = UIView()
        anchor.isUserInteractionEnabled = false
        anchor.isAccessibilityElement = false
        context.coordinator.update(self)
        return anchor
    }
    func updateUIView(_ uiView: UIView, context: Context) { context.coordinator.update(self) }
    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.detach() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var target: UIView?
        private var configuration: VisionHardwarePointer?
        private var recognizers: [UIGestureRecognizer] = []
        private var button: PointerAction?
        private var point = CGPoint(x: 0.5, y: 0.5)
        private var trackpadTranslation = CGPoint.zero
        private var wheelTranslation = CGPoint.zero
        private var scrolling = false
        private var wheelOpen = false

        func update(_ next: VisionHardwarePointer) {
            let reset = target !== next.displayView || configuration?.source != next.source
                || configuration?.enabled != next.enabled || configuration?.videoSize != next.videoSize
            if reset {
                releaseInput()
                // Cancels any recognizer still following an old source or disabled capture.
                recognizers.forEach { $0.isEnabled = false }
            }
            if target !== next.displayView { detach(); attach(to: next.displayView) }
            configuration = next
            recognizers.forEach { $0.isEnabled = next.enabled }
        }

        private func attach(to view: UIView) {
            target = view
            let hardware = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
            let pointer = VisionPointerRecognizer()
            pointer.allowedTouchTypes = hardware
            pointer.cancelsTouchesInView = false
            pointer.delegate = self
            pointer.changed = { [weak self] state, location, secondary in
                self?.pointer(state, at: location, secondary: secondary)
            }
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:)))
            hover.allowedTouchTypes = hardware
            hover.delegate = self
            var installed: [UIGestureRecognizer] = [pointer, hover]
            for (mask, selector) in [(UIScrollTypeMask.continuous, #selector(trackpad(_:))),
                                     (UIScrollTypeMask.discrete, #selector(wheel(_:)))] {
                let pan = UIPanGestureRecognizer(target: self, action: selector)
                pan.allowedTouchTypes = hardware
                pan.allowedScrollTypesMask = mask
                pan.maximumNumberOfTouches = 0
                pan.cancelsTouchesInView = false
                pan.delegate = self
                installed.append(pan)
            }
            recognizers = installed
            view.isUserInteractionEnabled = true
            installed.forEach(view.addGestureRecognizer)
        }

        func detach() {
            releaseInput()
            if let target { recognizers.forEach(target.removeGestureRecognizer) }
            recognizers = []
            target = nil
            configuration = nil
        }

        private var rect: CGRect {
            guard let target, let size = configuration?.videoSize,
                  size.width > 0, size.height > 0, target.bounds.width > 0, target.bounds.height > 0 else { return .zero }
            let scale = min(target.bounds.width / size.width, target.bounds.height / size.height)
            let width = size.width * scale, height = size.height * scale
            return CGRect(x: target.bounds.midX - width / 2, y: target.bounds.midY - height / 2,
                          width: width, height: height)
        }

        private func normalized(_ location: CGPoint, clamped: Bool) -> CGPoint? {
            guard let target, let configuration else { return nil }
            if !clamped {
                return VisionInputGeometry.normalized(location, bounds: target.bounds, videoSize: configuration.videoSize)
            }
            let picture = rect
            guard picture.width > 0, picture.height > 0 else { return nil }
            return CGPoint(x: min(max((location.x - picture.minX) / picture.width, 0), 1),
                           y: min(max((location.y - picture.minY) / picture.height, 0), 1))
        }

        private func pointer(_ state: UIGestureRecognizer.State, at location: CGPoint, secondary: Bool) {
            guard let configuration, configuration.enabled else { return }
            switch state {
            case .began:
                releaseInput()
                guard let position = normalized(location, clamped: false) else { return }
                point = position
                configuration.pointerBegan()
                configuration.send(.pointer(.move, x: point.x, y: point.y))
                let down: PointerAction = secondary ? .rightDown : .leftDown
                button = down
                configuration.send(.pointer(down, x: point.x, y: point.y))
            case .changed:
                guard button != nil, let position = normalized(location, clamped: true) else { return }
                point = position
                configuration.send(.pointer(.move, x: point.x, y: point.y))
            case .ended, .cancelled, .failed:
                if let position = normalized(location, clamped: true), button != nil { point = position }
                releaseInput()
            default: break
            }
        }

        @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
            guard let configuration, configuration.enabled,
                  gesture.state == .began || gesture.state == .changed,
                  let position = normalized(gesture.location(in: target), clamped: button != nil) else { return }
            point = position
            configuration.send(.pointer(.move, x: point.x, y: point.y))
        }
        @objc private func trackpad(_ gesture: UIPanGestureRecognizer) { scroll(gesture, phased: true) }
        @objc private func wheel(_ gesture: UIPanGestureRecognizer) { scroll(gesture, phased: false) }

        private func scroll(_ gesture: UIPanGestureRecognizer, phased: Bool) {
            guard let configuration, configuration.enabled else { return }
            let location = gesture.location(in: target)
            switch gesture.state {
            case .began:
                configuration.momentum.stop()
                guard let position = normalized(location, clamped: false) else { return }
                point = position
                if phased {
                    trackpadTranslation = .zero
                    scrolling = true
                    configuration.send(.scrollGesture(.began, x: point.x, y: point.y))
                } else { wheelTranslation = .zero; wheelOpen = true }
                emitScroll(gesture.translation(in: target), phased: phased)
            case .changed:
                // A phased pan rejected at its start must never produce later deltas.
                guard phased ? scrolling : wheelOpen else { return }
                if let position = normalized(location, clamped: false) { point = position }
                else { return }
                emitScroll(gesture.translation(in: target), phased: phased)
            case .ended:
                let accepted = phased ? scrolling : wheelOpen
                if let final = normalized(location, clamped: true), accepted { point = final }
                if phased ? scrolling : wheelOpen { emitScroll(gesture.translation(in: target), phased: phased) }
                finishScroll(phased: phased)
                if phased && accepted && rect.width > 0 && rect.height > 0 {
                    let coastPoint = point, picture = rect
                    let original = configuration
                    configuration.momentum.start(velocity: gesture.velocity(in: target), onBegin: {
                        original.send(.scrollGesture(.momentumBegan, x: coastPoint.x, y: coastPoint.y))
                    }, onStep: { [weak self] delta in
                        guard let self, self.configuration?.enabled == true, self.configuration?.source == original.source,
                              picture.width > 0, picture.height > 0 else { return }
                        original.send(.scroll(x: coastPoint.x, y: coastPoint.y, dx: delta.x / picture.width, dy: delta.y / picture.height))
                    }, onEnd: {
                        original.send(.scrollGesture(.momentumEnded, x: coastPoint.x, y: coastPoint.y))
                    })
                }
            case .cancelled, .failed:
                finishScroll(phased: phased)
            default: break
            }
        }

        private func emitScroll(_ translation: CGPoint, phased: Bool) {
            let picture = rect
            guard picture.width > 0, picture.height > 0 else { return }
            let previous = phased ? trackpadTranslation : wheelTranslation
            let dx = (translation.x - previous.x) / picture.width
            let dy = (translation.y - previous.y) / picture.height
            if dx != 0 || dy != 0 { configuration?.send(.scroll(x: point.x, y: point.y, dx: dx, dy: dy)) }
            if phased { trackpadTranslation = translation } else { wheelTranslation = translation }
        }

        private func finishScroll(phased: Bool) {
            if phased, scrolling {
                configuration?.send(.scrollGesture(.ended, x: point.x, y: point.y))
                scrolling = false
            }
            if phased { trackpadTranslation = .zero } else { wheelTranslation = .zero; wheelOpen = false }
        }

        private func releaseInput() {
            configuration?.momentum.stop()
            if let button {
                configuration?.send(.pointer(button == .rightDown ? .rightUp : .leftUp, x: point.x, y: point.y))
                self.button = nil
                configuration?.pointerEnded()
            }
            finishScroll(phased: true)
            wheelTranslation = .zero
            wheelOpen = false
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            // Coexist within the hardware group; the immediate pointer recognizer wins a hardware
            // click over ancestor tap recognizers, avoiding a duplicate SwiftUI spatial tap.
            recognizers.contains { $0 === otherGestureRecognizer }
        }
    }
}

/// Tracks button presses from actual mouse/trackpad touches, never direct spatial pinches.
private final class VisionPointerRecognizer: UIGestureRecognizer {
    var changed: (UIGestureRecognizer.State, CGPoint, Bool) -> Void = { _, _, _ in }
    private var activeTouch: UITouch?
    private var secondary = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard activeTouch == nil,
              let touch = touches.first(where: { $0.type == .indirectPointer }) else { return }
        activeTouch = touch
        secondary = event.buttonMask.contains(.secondary)
        state = .began
        changed(.began, touch.location(in: view), secondary)
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        state = .changed
        changed(.changed, touch.location(in: view), secondary)
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, state: .ended)
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(touches, state: .cancelled)
    }
    private func finish(_ touches: Set<UITouch>, state next: UIGestureRecognizer.State) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        changed(next, touch.location(in: view), secondary)
        state = next
    }
    override func reset() {
        if let touch = activeTouch { changed(.cancelled, touch.location(in: view), secondary) }
        activeTouch = nil
        secondary = false
        super.reset()
    }
}
