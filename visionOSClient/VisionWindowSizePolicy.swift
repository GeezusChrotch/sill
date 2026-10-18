import Foundation
import CoreGraphics

/// One source selection supplies one preferred native size. Viewport or later encoded sizes do
/// not revise it, so fitting the Mac window cannot feed back into native scene sizing.
enum VisionWindowSizePolicy {
    enum Toolbar { case top, left, hidden }
    static let login = CGSize(width: 580, height: 480)
    static let desktopDefault = CGSize(width: 1200, height: 800)
    static let minimum = CGSize(width: 440, height: 360)
    static let maximum = CGSize(width: 1400, height: 1050)

    static func sceneSize(source: CGSize, toolbar: Toolbar) -> CGSize? {
        guard source.width.isFinite, source.height.isFinite,
              source.width > 0, source.height > 0 else { return nil }
        let chrome: CGSize
        switch toolbar {
        case .top: chrome = CGSize(width: 16, height: 126)
        case .left: chrome = CGSize(width: 172, height: 16)
        case .hidden: chrome = CGSize(width: 16, height: 16)
        }
        let available = CGSize(width: maximum.width - chrome.width, height: maximum.height - chrome.height)
        let scale = min(1, available.width / source.width, available.height / source.height)
        return CGSize(width: min(maximum.width, max(minimum.width, source.width * scale + chrome.width)),
                      height: min(maximum.height, max(minimum.height, source.height * scale + chrome.height)))
    }
}
