import UIKit

// Matches the iPad scroll decay and phased momentum implementation.
final class VisionScrollMomentum: NSObject {
    /// Lift-off speed, in points per second, below which a pan just stops. Anything slower is a
    /// placement, not a flick — roughly where UIScrollView's own coast stops being noticeable.
    private static let minimumSpeed: CGFloat = 150
    /// The rate the decay is defined at, and the rate the link is pinned to: a 120 Hz display
    /// would otherwise double the message rate for no visible gain on a 60 fps stream.
    private static let tickRate: Double = 60
    /// Velocity kept per 1/60 s tick. At 0.96 a coast travels ≈ 0.42 s × lift-off speed, and a
    /// typical 1000–3000 pt/s flick coasts for ~1.6–2.1 s before `stopBelow` (a gentle 300 pt/s
    /// one for ~1.1 s), inside the 1.5–2.5 s tail of a Mac trackpad. By the same arithmetic 0.95
    /// gives ~1.3–1.7 s, short of it, and 0.97 ~2.2–2.8 s, past it. Tune here after trying it.
    private static let decayPerTick: Double = 0.96
    /// Stop once a tick would move less than this many points: past here the tail is invisible,
    /// and still sending it would only hold the Mac's gesture open.
    private static let stopBelow: Double = 0.3

    private var link: CADisplayLink?
    /// Points per second, decaying.
    private var velocity = CGPoint.zero
    private var lastTimestamp: CFTimeInterval = 0
    private var onStep: ((CGPoint) -> Void)?
    private var onEnd: (() -> Void)?

    /// Starts a coast if `velocity` (points per second, from the pan recognizer) is a flick, and
    /// does nothing otherwise. `onBegin` and the first step fire straight away, so the momentum
    /// follows the gesture's end without waiting a frame, as a real trackpad's does.
    func start(velocity: CGPoint, onBegin: () -> Void,
               onStep: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
        stop()
        guard hypot(velocity.x, velocity.y) > Self.minimumSpeed else { return }
        self.velocity = velocity
        self.onStep = onStep
        self.onEnd = onEnd
        onBegin()
        let tick = 1 / Self.tickRate
        onStep(CGPoint(x: velocity.x * tick, y: velocity.y * tick))

        // The link retains this object until it is invalidated, which `stop` always does, and a
        // run always ends on its own within a few seconds.
        let link = CADisplayLink(target: self, selector: #selector(advance))
        let rate = Float(Self.tickRate)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = CACurrentMediaTime()
    }

    /// Ends the run in progress, if any, firing its `onEnd`. Safe to call at any time.
    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        let end = onEnd
        onStep = nil
        onEnd = nil
        end?()
    }

    @objc private func advance(_ link: CADisplayLink) {
        // Real elapsed time rather than an assumed 1/60 s, so a skipped frame does not slow the
        // coast; clamped so a long stall (the app switcher) cannot turn into one big jump.
        let now = link.targetTimestamp
        let dt = min(now - lastTimestamp, 0.1)
        guard dt > 0 else { return }
        lastTimestamp = now

        let decay = CGFloat(pow(Self.decayPerTick, dt * Self.tickRate))
        velocity.x *= decay
        velocity.y *= decay
        // The stop rule is per 60 Hz tick whatever the actual frame interval was.
        guard Double(hypot(velocity.x, velocity.y)) / Self.tickRate >= Self.stopBelow else {
            stop()
            return
        }
        onStep?(CGPoint(x: velocity.x * dt, y: velocity.y * dt))
    }
}
