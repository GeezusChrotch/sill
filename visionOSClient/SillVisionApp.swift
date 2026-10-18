import SwiftUI

@main
struct SillVisionApp: App {
    var body: some Scene {
        WindowGroup {
            VisionSessionView()
        }
        .windowStyle(.plain)
        .defaultSize(width: 1200, height: 800)
    }
}
