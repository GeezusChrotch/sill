import SwiftUI
import UIKit

private final class VisionSceneReference { weak var value: UIWindowScene? }

/// Bind the native scene and hydrate its state before ContentView performs connection startup.
struct VisionSessionView: View {
    let windowID: UUID?
    let isSecondary: Bool
    @State private var seed: VisionWindowSeed?
    @State private var ready = false
    @State private var nativeSessionID: String?
    @State private var owningScene = VisionSceneReference()
    @SceneStorage("Sill.spatialWorkspace.v1") private var workspace = ""
    @SceneStorage("Sill.spatialToolbarAutomatic") private var automatic = true
    @SceneStorage("Sill.spatialMouseMode") private var mouse = false
    @SceneStorage("Sill.spatialTextScale") private var scale = 0.0
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    init(windowID: UUID? = nil, isSecondary: Bool = false) {
        self.windowID = windowID
        self.isSecondary = isSecondary
        _seed = State(initialValue: windowID.flatMap { VisionWindowLaunches.shared.seed(for: $0) })
    }
    private var preferences: VisionScenePreferences {
        get { .init(toolbarAutomatic: automatic, mouseMode: mouse, textScale: scale) }
        nonmutating set { automatic = newValue.toolbarAutomatic; mouse = newValue.mouseMode; scale = newValue.textScale }
    }
    var body: some View {
        ZStack {
            Color.clear
            if ready { session }
        }
        .background(VisionSceneSetBinding(onBind: bind).frame(width: 1, height: 1))
        .task {
            // A missing native bridge must not leave an indefinitely blank app. Native
            // SceneStorage can still restore; ledger replay waits for a real owning scene.
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            if !ready { ready = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, let scene = owningScene.value, scene.activationState == .foregroundActive { bind(scene) }
        }
        .onChange(of: workspace) { _, _ in save() }
        .onChange(of: automatic) { _, _ in save() }
        .onChange(of: mouse) { _, _ in save() }
        .onChange(of: scale) { _, _ in save() }
    }
    @ViewBuilder private var session: some View {
        #if DEBUG
        if VisionSceneSetRecovery.fixture {
            VStack {
                Text("Scene-set fixture: \(windowID?.uuidString ?? "primary")")
                Text("Mouse \(mouse ? "on" : "off"), scale \(scale), auto \(automatic ? "on" : "off")")
            }
            .onAppear { print("SCENE_SET fixture key=\(VisionSceneSet.key(windowID)) mouse=\(mouse) scale=\(scale) auto=\(automatic)") }
        } else if UserDefaults.standard.bool(forKey: "SillNativeGeometry") {
            VisionNativeGeometryFixture()
        } else { content }
        #else
        content
        #endif
    }
    private var content: some View {
        ContentView(spatialSeed: seed, spatialManualConnect: isSecondary && seed == nil,
                    spatialWorkspace: $workspace)
            .environment(\.spatialSceneID, windowID)
            .environment(\.spatialNativeSession, nativeSessionID)
            .environment(\.spatialScenePreferences, Binding(get: { preferences }, set: { preferences = $0 }))
            .onAppear { if let windowID { VisionWindowLaunches.shared.discard(windowID) } }
    }
    private func bind(_ scene: UIWindowScene) {
        owningScene.value = scene
        guard !isSecondary || windowID != nil else { ready = true; return }
        nativeSessionID = scene.session.persistentIdentifier
        let recovery = VisionSceneSetRecovery.shared
        #if DEBUG
        if VisionSceneSetRecovery.fixture { recovery.seedFixture() }
        #endif
        let stored = recovery.bind(windowID, to: scene)
        if !ready, seed == nil, VisionWorkspace.decode(workspace) == nil, let stored {
            workspace = stored.workspace.encoded
            preferences = stored.preferences
        }
        ready = true
        save()
        if scene.activationState == .foregroundActive { recover(from: scene) }
    }
    private func save() {
        guard !isSecondary || windowID != nil, let scene = owningScene.value,
              let value = VisionWorkspace.decode(workspace) else { return }
        VisionSceneSetRecovery.shared.save(windowID, session: scene.session.persistentIdentifier,
                                           workspace: value, preferences: preferences)
    }
    private func recover(from scene: UIWindowScene) {
        VisionSceneSetRecovery.shared.recover(from: scene) { id in
            if let id { openWindow(id: "sill-session", value: id) }
            else { openWindow(id: "sill-main") }
        }
    }
}
