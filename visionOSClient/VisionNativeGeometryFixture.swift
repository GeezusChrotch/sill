#if DEBUG
import SwiftUI
import UIKit

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
        .background {
            if ProcessInfo.processInfo.arguments.contains("-SillNativeLargeResize1") {
                VisionNativeLargeResizeProbe().frame(width: 1, height: 1)
            }
        }
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
/// Opt-in diagnostic for a programmatic resize beyond the old ceiling. Waits for
/// the normal scene bridge to finish Desktop aspect locking; never drives a live client.
private struct VisionNativeLargeResizeProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> ProbeView { ProbeView() }
    func updateUIView(_ view: ProbeView, context: Context) {}
    static func dismantleUIView(_ view: ProbeView, coordinator: ()) { view.stop() }

    final class ProbeView: UIView {
        private var task: Task<Void, Never>?
        func stop() { task?.cancel(); task = nil }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            stop()
            guard let scene = window?.windowScene else { return }
            task = Task { @MainActor [weak self, weak scene] in
                guard let self, let scene else { return }
                let source = CGSize(width: 3840, height: 2160)
                let geometry = VisionWindowSizePolicy.geometry(source: source)!
                for _ in 0..<100 {
                    do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                    guard self.window?.windowScene === scene else { return }
                    let actual = self.window?.bounds.size ?? .zero
                    guard scene.effectiveGeometry.resizingRestrictions == .uniform,
                          VisionWindowSizePolicy.matchesAspect(actual, source: source) else { continue }
                    let requested = CGSize(width: 2400, height: 1350)
                    print("NATIVE_LARGE_RESIZE request=\(requested) before=\(actual) maximum=\(scene.effectiveGeometry.maximumSize)")
                    scene.requestGeometryUpdate(.Vision(size: requested, minimumSize: geometry.minimum,
                                                         maximumSize: geometry.maximum, resizingRestrictions: .uniform)) { error in
                        print("NATIVE_LARGE_RESIZE declined=\(error.localizedDescription)")
                    }
                    for _ in 0..<30 {
                        do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
                        guard self.window?.windowScene === scene else { return }
                        let observed = self.window?.bounds.size ?? .zero
                        if abs(observed.width - requested.width) <= 1 && abs(observed.height - requested.height) <= 1,
                           scene.effectiveGeometry.resizingRestrictions == .uniform {
                            print("NATIVE_LARGE_RESIZE confirmed actual=\(observed) maximum=\(scene.effectiveGeometry.maximumSize) restriction=uniform")
                            return
                        }
                    }
                    print("NATIVE_LARGE_RESIZE unconfirmed actual=\(self.window?.bounds.size ?? .zero) maximum=\(scene.effectiveGeometry.maximumSize)")
                    return
                }
                print("NATIVE_LARGE_RESIZE Desktop aspect lock not observed")
            }
        }
    }
}
#endif
