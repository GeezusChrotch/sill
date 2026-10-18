import Foundation
import CoreGraphics

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
func sameRatio(_ a: CGSize, _ b: CGSize) -> Bool {
    abs(a.width / a.height / (b.width / b.height) - 1) < 0.000001
}
// Includes cases where independent axis clamping formerly changed the aspect, plus
// windows that cannot simultaneously satisfy both old per-axis minimums and maximums.
for source in [CGSize(width: 1000, height: 700), CGSize(width: 600, height: 1200),
               CGSize(width: 60, height: 40), CGSize(width: 10000, height: 6000),
               CGSize(width: 4000, height: 200), CGSize(width: 120, height: 2400)] {
    guard let geometry = VisionWindowSizePolicy.geometry(source: source) else { fatalError("Valid source rejected") }
    for scene in [geometry.minimum, geometry.preferred, geometry.maximum] {
        expect(sameRatio(scene, source), "Scene geometry changed source aspect: \(source) → \(scene)")
        expect(scene.width <= 1400.000001 && scene.height <= 1050.000001, "Maximum envelope violated")
        expect(scene.width >= geometry.minimum.width && scene.height >= geometry.minimum.height, "Below resize minimum")
    }
    for fraction: CGFloat in [0, 0.1, 0.5, 0.9, 1] {
        // Native .uniform scales the scene, while ornaments occupy no picture space.
        let scene = CGSize(width: geometry.minimum.width + fraction * (geometry.maximum.width - geometry.minimum.width),
                           height: geometry.minimum.height + fraction * (geometry.maximum.height - geometry.minimum.height))
        let fittedPicture = CGSize(width: min(scene.width, scene.height * source.width / source.height),
                                   height: min(scene.height, scene.width * source.height / source.width))
        expect(abs(fittedPicture.width - scene.width) < 0.000001 && abs(fittedPicture.height - scene.height) < 0.000001,
               "Uniform resizing introduced letterboxing at \(scene)")
    }
}
let ordinary = VisionWindowSizePolicy.geometry(source: CGSize(width: 1000, height: 700))!
expect(ordinary.preferred == CGSize(width: 1000, height: 700), "Ordinary source should open at source size")
expect(VisionWindowSizePolicy.geometry(source: CGSize(width: 60, height: 40))!.preferred == CGSize(width: 440, height: 440.0 * 2 / 3),
       "Tiny source should enlarge uniformly to the minimum envelope")
// Desktop capture can be Retina landscape, portrait, or an ultrawide display. Use
// decoded pixels (not the previous 1200×800 default) and keep exact ratio at every bound.
for desktop in [CGSize(width: 3024, height: 1964), CGSize(width: 1920, height: 1080),
                CGSize(width: 2160, height: 3840), CGSize(width: 5120, height: 1440)] {
    let geometry = VisionWindowSizePolicy.geometry(source: desktop)!
    for size in [geometry.minimum, geometry.preferred, geometry.maximum] {
        expect(sameRatio(size, desktop), "Desktop lost decoded source ratio")
    }

}
for bad in [CGSize.zero, CGSize(width: 0, height: 10), CGSize(width: -1, height: 10), CGSize(width: CGFloat.infinity, height: 10), CGSize(width: 10, height: CGFloat.nan)] {
    expect(VisionWindowSizePolicy.geometry(source: bad) == nil, "Invalid geometry must wait for a real source")
}


expect(VisionWindowSizePolicy.matchesAspect(CGSize(width: 1400, height: 787.5), source: CGSize(width: 3840, height: 2160)), "Matching native Desktop geometry rejected")
expect(!VisionWindowSizePolicy.matchesAspect(CGSize(width: 1400, height: 875), source: CGSize(width: 3840, height: 2160)), "Prior window aspect must not be locked for Desktop")
expect(VisionWindowSizePolicy.matchesAspect(CGSize(width: 1400, height: 788), source: CGSize(width: 3840, height: 2160)), "Point-rounded native geometry rejected")
expect(!VisionWindowSizePolicy.matchesAspect(.zero, source: CGSize(width: 3840, height: 2160)), "Detached window cannot confirm geometry")

print("vision-window-size: source scaling, invalid dimensions and observed native aspect checks passed")
