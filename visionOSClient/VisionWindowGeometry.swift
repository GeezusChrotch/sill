import SwiftUI
import UIKit
import StreamProtocol

/// A scene-local bridge is needed because SwiftUI has no imperative scene-size request API.
/// It never enumerates UIApplication windows or applies changes to a sibling scene.
struct VisionWindowGeometry: UIViewRepresentable {
    @ObservedObject var client: StreamClient

    func makeUIView(context: Context) -> VisionWindowGeometryView {
        VisionWindowGeometryView()
    }

    func updateUIView(_ view: VisionWindowGeometryView, context: Context) {
        #if DEBUG
        // Exact-size mock/live harness frames are visual test fixtures, not scene-size requests.
        if LayoutHarness.Spec.fromLaunchArguments != nil { return }
        #endif
        view.update(client: client)
    }

    static func dismantleUIView(_ view: VisionWindowGeometryView, coordinator: ()) {
        view.removeObservers()
    }
}

final class VisionWindowGeometryView: UIView {
    private enum Token: Equatable {
        case login
        case source(Date?, StreamSource)
    }
    private weak var client: StreamClient?
    private weak var owningScene: UIWindowScene?
    private var applied: Token?
    private var waitingForDimensions: Token?
    private var hasSizedConnectedSource = false
    private var disconnected = false
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        observers = [
            NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let current = self.owningScene, let scene = note.object as? UIWindowScene, scene === current else { return }
                self.disconnected = true
                self.applied = nil
            },
            NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let current = self.owningScene, let scene = note.object as? UIWindowScene, scene === current else { return }
                self.disconnected = false
                self.applySize()
            }
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { removeObservers() }

    func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let scene = window?.windowScene else { return }
        owningScene = scene
        if let client { VisionSceneSessionLifecycle.attach(client: client, to: scene) }
        applySize()
    }

    func update(client: StreamClient) {
        self.client = client
        if let scene = owningScene { VisionSceneSessionLifecycle.attach(client: client, to: scene) }
        applySize()
    }

    private func applySize() {
        guard !disconnected, let client, let scene = owningScene else { return }
        let token: Token
        let desired: CGSize
        if !client.connected {
            token = .login
            hasSizedConnectedSource = false
            desired = VisionWindowSizePolicy.login
        } else {
            token = .source(client.connectedAt, client.active)
            guard token != applied else { return }
            if client.active == .desktop {
                // No trustworthy Desktop aspect is carried by the protocol. The first Desktop
                // gets a comfortable default; later picks keep the person's current native size.
                applied = token // Record even a no-resize transition: A → Desktop → A is new.
                let initialSize = hasSizedConnectedSource ? nil : VisionWindowSizePolicy.desktopDefault
                hasSizedConnectedSource = true
                request(initialSize, in: scene)
                return
            }
            let source: CGSize
            switch client.active {
            case .window(let id):
                if let snapshot = client.spatialPreferredSourceSize, snapshot.source == client.active {
                    source = snapshot.size
                } else {
                    // Host-initiated selections have no local request snapshot.
                    guard let window = client.windows.first(where: { $0.id == id }) else {
                        releaseWhileWaiting(token, in: scene)
                        return
                    }
                    source = CGSize(width: window.width, height: window.height)
                }
            case .desktop:
                // Desktop has no source-bound catalog dimensions. An arbitrary latest video size
                // can still belong to the previous window, so retain the person's current size.
                return
            case .none:
                applied = token
                request(nil, in: scene) // Waiting for a selection must not retain a previous lock.
                return
            }
            guard let geometry = VisionWindowSizePolicy.geometry(source: source) else {
                releaseWhileWaiting(token, in: scene)
                return
            }
            waitingForDimensions = nil
            applied = token // Record before requesting; viewport updates cannot request themselves.
            hasSizedConnectedSource = true
            request(geometry.preferred, in: scene, geometry: geometry)
            return
        }
        guard token != applied else { return }
        applied = token // Store before requesting: a geometry update must never request itself.
        request(desired, in: scene)
    }

    private func releaseWhileWaiting(_ token: Token, in scene: UIWindowScene) {
        // Missing dimensions must release a previous window's ratio, but remain retryable
        // when a later catalog supplies them. Do not send on every observed client change.
        guard waitingForDimensions != token else { return }
        waitingForDimensions = token
        request(nil, in: scene)
    }

    private func request(_ desired: CGSize?, in scene: UIWindowScene,
                         geometry: VisionWindowSizePolicy.WindowGeometry? = nil) {
        scene.requestGeometryUpdate(.Vision(size: desired,
                                             minimumSize: geometry?.minimum ?? VisionWindowSizePolicy.minimum,
                                             maximumSize: geometry?.maximum ?? VisionWindowSizePolicy.maximum,
                                             resizingRestrictions: geometry == nil ? .freeform : .uniform)) { error in
            print("spatial window size request declined: \(error.localizedDescription)")
        }
    }
}
