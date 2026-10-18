#if DEBUG
import SwiftUI

/// Native scene diagnostic: no fixed frame or LayoutHarness. Never browses or connects.
struct VisionNativeGeometryFixture: View {
    @StateObject private var client = MockCatalog.client(active: .none)
    @State private var source = CGSize(width: 1440, height: 900)
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.red
                Rectangle().fill(.blue).aspectRatio(source, contentMode: .fit)
                Text("Native geometry fixture \(Int(proxy.size.width))×\(Int(proxy.size.height))")
            }
            .onChange(of: proxy.size, initial: true) { _, size in
                print("NATIVE_GEOMETRY content=\(size) source=\(source)")
            }
        }
        .background(VisionWindowGeometry(client: client).frame(width: 1, height: 1))
        .task {
            try? await Task.sleep(for: .seconds(2))
            client.active = .window(102)
            try? await Task.sleep(for: .seconds(4))
            source = CGSize(width: 3840, height: 2160)
            client.active = .desktop
            client.setNativeGeometryFixtureDesktopSize(source)
            try? await Task.sleep(for: .seconds(5))
            print("NATIVE_GEOMETRY fixture completed")
        }
    }
}
#endif
