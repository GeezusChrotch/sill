import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func size(_ width: CGFloat, _ height: CGFloat, _ toolbar: VisionWindowSizePolicy.Toolbar) -> CGSize {
    guard let result = VisionWindowSizePolicy.sceneSize(source: CGSize(width: width, height: height), toolbar: toolbar) else { fatalError("Valid source rejected") }
    expect(result.width >= 440 && result.width <= 1400 && result.height >= 360 && result.height <= 1050, "Scene bounds violated")
    return result
}
let landscape = size(1000, 700, .top)
expect(landscape == CGSize(width: 1016, height: 894), "Top chrome must fit source without scaling ordinary windows")
let left = size(1000, 700, .left)
expect(left == CGSize(width: 1016, height: 716), "Left ornament must reserve no stream viewport space")
let hidden = size(1000, 700, .hidden)
expect(hidden == CGSize(width: 1016, height: 716), "Hidden toolbar reserves only stream padding")
let portrait = size(600, 1200, .top)
expect(portrait.height == 1050 && portrait.width < portrait.height, "Portrait fit must stay bounded and portrait")
expect(abs((portrait.width - 16) / (portrait.height - 194) - 0.5) < 0.001, "Fit changed portrait source aspect")
expect(size(60, 40, .left) == VisionWindowSizePolicy.minimum, "Tiny sources must remain usable")
let huge = size(10000, 6000, .left)
expect(abs((huge.width - 16) / (huge.height - 16) - 10000.0 / 6000.0) < 0.001, "Huge fit changed source aspect")
for bad in [CGSize.zero, CGSize(width: 0, height: 10), CGSize(width: -1, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10, height: CGFloat.nan)] {
    expect(VisionWindowSizePolicy.sceneSize(source: bad, toolbar: .top) == nil, "Invalid geometry must wait for a real source")
}
print("vision-window-size: source aspect, bounds, toolbar chrome and invalid-source checks passed")
