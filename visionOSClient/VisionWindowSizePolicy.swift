import Foundation
import CoreGraphics

/// Scene and picture have the same ratio. Both toolbars are ornaments, and the picture
/// has no additive padding: uniform native resizing therefore preserves the source aspect.
/// Only the selection snapshot supplies this geometry, never a resized viewport/video frame.
enum VisionWindowSizePolicy {
    static let login = CGSize(width: 580, height: 480)
    static let desktopDefault = CGSize(width: 1200, height: 800)
    static let minimum = CGSize(width: 440, height: 360)
    static let maximum = CGSize(width: 1400, height: 1050)

    struct WindowGeometry {
        let preferred: CGSize
        let minimum: CGSize
        let maximum: CGSize
    }

    static func geometry(source: CGSize) -> WindowGeometry? {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0 else { return nil }
        // Fit both envelopes uniformly. Independent per-axis clamping would change the ratio,
        // especially for tiny, very wide, or very tall windows. The minimum envelope is soft:
        // its shorter dimension may be below the login/Desktop minimum for unusual ratios.
        let minimumScale = min(minimum.width / source.width, minimum.height / source.height)
        let maximumScale = min(maximum.width / source.width, maximum.height / source.height)
        func scaled(_ scale: CGFloat) -> CGSize {
            CGSize(width: source.width * scale, height: source.height * scale)
        }
        return WindowGeometry(preferred: scaled(min(maximumScale, max(minimumScale, 1))),
                              minimum: scaled(minimumScale), maximum: scaled(maximumScale))
    }
}
