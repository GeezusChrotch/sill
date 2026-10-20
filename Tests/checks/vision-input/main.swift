import Foundation
import CoreGraphics

let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
let wide = CGSize(width: 1920, height: 1080)
func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
    print("ok \(message)")
}
let center = VisionInputGeometry.normalized(CGPoint(x: 500, y: 500), bounds: bounds, videoSize: wide)
expect(center == CGPoint(x: 0.5, y: 0.5), "center maps to video center")
expect(VisionInputGeometry.normalized(CGPoint(x: 500, y: 100), bounds: bounds, videoSize: wide) == nil, "top letterbox rejects input")
expect(VisionInputGeometry.normalized(CGPoint(x: 500, y: 900), bounds: bounds, videoSize: wide) == nil, "bottom letterbox rejects input")
expect(VisionInputGeometry.normalized(.zero, bounds: bounds, videoSize: .zero) == nil, "no frame rejects input")
expect(VisionInputGeometry.normalized(.zero, bounds: .zero, videoSize: wide) == nil, "zero view rejects input")
let portrait = CGSize(width: 1080, height: 1920)
expect(VisionInputGeometry.normalized(CGPoint(x: 100, y: 500), bounds: bounds, videoSize: portrait) == nil, "side letterbox rejects input")
let offset = CGRect(x: 50, y: 100, width: 800, height: 600)
expect(VisionInputGeometry.normalized(CGPoint(x: 450, y: 400), bounds: offset, videoSize: wide) == CGPoint(x: 0.5, y: 0.5), "offset bounds normalize correctly")
let quarter = VisionInputGeometry.normalized(CGPoint(x: 250, y: 359.375), bounds: bounds, videoSize: wide)
expect(quarter.map { abs($0.x - 0.25) < 0.000001 && abs($0.y - 0.25) < 0.000001 } == true, "quarter location respects letterbox offset")

// The video and UIKit overlay are framed to the same inner rect. Exercise mapping
// in scene coordinates so native resize corners/black margins never reach the Mac.
for source in [wide, portrait, CGSize(width: 1000, height: 700)] {
    let geometry = VisionWindowSizePolicy.geometry(source: source)!
    for scene in [geometry.minimum, geometry.preferred, geometry.maximum] {
        let inner = VisionWindowSizePolicy.streamRect(scene: scene, source: source)
        let mapper = ActualInputMapper(bounds: inner, videoSize: source)
        for point in [CGPoint(x: 0, y: 0), CGPoint(x: scene.width - 1, y: scene.height - 1),
                      CGPoint(x: inner.minX / 2, y: inner.midY), CGPoint(x: inner.midX, y: inner.minY / 2)] {
            expect(mapper.normalized(point, clamped: false) == nil, "Black border must reject remote input")
        }
        for unit in [CGPoint(x: 0.001, y: 0.001), CGPoint(x: 0.999, y: 0.999), CGPoint(x: 0.5, y: 0.5)] {
            let point = CGPoint(x: inner.minX + inner.width * unit.x, y: inner.minY + inner.height * unit.y)
            let mapped = mapper.normalized(point, clamped: false)!
            expect(abs(mapped.x - unit.x) < 0.000001 && abs(mapped.y - unit.y) < 0.000001,
                   "Remote edge controls must retain correct normalized coordinates after inset/resize")
        }
    }
}
print("vision-input: bordered scene edge rejection and inner coordinate mapping passed")

let actualLetterbox = ActualInputMapper(bounds: bounds, videoSize: wide)
expect(actualLetterbox.normalized(.zero, clamped: false) == nil, "Actual UIKit transform rejects letterbox clicks")
expect(actualLetterbox.normalized(.zero, clamped: true)?.y == 0, "Actual UIKit transform retains drags past picture edge")
expect(ActualInputMapper(bounds: bounds, videoSize: .zero).normalized(.zero, clamped: false) == nil,
       "Actual UIKit transform rejects unknown video")
