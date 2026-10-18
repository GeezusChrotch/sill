import SwiftUI
import UIKit
import StreamProtocol

/// A scene-local bridge is needed because SwiftUI has no imperative scene-size request API.
/// It never enumerates UIApplication windows or applies changes to a sibling scene.
struct VisionWindowGeometry: UIViewRepresentable {
    @ObservedObject var client: StreamClient
    @SceneStorage("Sill.spatialToolbarPosition") private var toolbarPosition = "top"
    @SceneStorage("Sill.spatialToolbarHidden") private var toolbarHidden = false

    func makeUIView(context: Context) -> VisionWindowGeometryView {
        VisionWindowGeometryView()
    }

    func updateUIView(_ view: VisionWindowGeometryView, context: Context) {
        #if DEBUG
        // Exact-size mock/live harness frames are visual test fixtures, not scene-size requests.
        if LayoutHarness.Spec.fromLaunchArguments != nil { return }
        #endif
        let toolbar: VisionWindowSizePolicy.Toolbar = toolbarHidden ? .hidden : toolbarPosition == "left" ? .left : .top
        view.update(client: client, toolbar: toolbar)
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
    private var toolbar = VisionWindowSizePolicy.Toolbar.top
    private var applied: Token?
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

    func update(client: StreamClient, toolbar: VisionWindowSizePolicy.Toolbar) {
        self.client = client
        self.toolbar = toolbar
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
            guard client.active != .none else { applied = nil; return }
            token = .source(client.connectedAt, client.active)
            guard token != applied else { return }
            if client.active == .desktop {
                // No trustworthy Desktop aspect is carried by the protocol. The first Desktop
                // gets a comfortable default; later picks keep the person's current native size.
                applied = token // Record even a no-resize transition: A → Desktop → A is new.
                guard !hasSizedConnectedSource else { return }
                hasSizedConnectedSource = true
                request(VisionWindowSizePolicy.desktopDefault, in: scene)
                return
            }
            let source: CGSize
            switch client.active {
            case .window(let id):
                if let snapshot = client.spatialPreferredSourceSize, snapshot.source == client.active {
                    source = snapshot.size
                } else {
                    // Host-initiated selections have no local request snapshot.
                    guard let window = client.windows.first(where: { $0.id == id }) else { return }
                    source = CGSize(width: window.width, height: window.height)
                }
            case .desktop:
                // Desktop has no source-bound catalog dimensions. An arbitrary latest video size
                // can still belong to the previous window, so retain the person's current size.
                return
            case .none: return
            }
            guard let size = VisionWindowSizePolicy.sceneSize(source: source, toolbar: toolbar) else { return }
            desired = size
            hasSizedConnectedSource = true
        }
        guard token != applied else { return }
        applied = token // Store before requesting: a geometry update must never request itself.
        request(desired, in: scene)
    }

    private func request(_ desired: CGSize, in scene: UIWindowScene) {
        scene.requestGeometryUpdate(.Vision(size: desired, minimumSize: VisionWindowSizePolicy.minimum,
                                             maximumSize: VisionWindowSizePolicy.maximum)) { error in
            print("spatial window size request declined: \(error.localizedDescription)")
        }
    }
}
