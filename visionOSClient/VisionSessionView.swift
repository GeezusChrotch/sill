import SwiftUI

/// Each scene owns the complete Sill root and therefore its own StreamClient and selection.
struct VisionSessionView: View {
    let windowID: UUID?
    @State private var seed: VisionWindowSeed?

    init(windowID: UUID? = nil) {
        self.windowID = windowID
        _seed = State(initialValue: windowID.flatMap { VisionWindowLaunches.shared.seed(for: $0) })
    }

    var body: some View {
        ContentView(spatialSeed: seed, spatialManualConnect: windowID != nil && seed == nil)
            .onAppear {
                if let windowID { VisionWindowLaunches.shared.discard(windowID) }
            }
    }
}
