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
            Button("Open synthetic second scene") {
                openWindow(id: "sill-session", value: UUID(uuidString: "00000000-0000-4000-8000-000000000029")!)
            }
            .onAppear {
                print("SCENE_SET fixture key=\(VisionSceneSet.key(windowID)) mouse=\(mouse) scale=\(scale) auto=\(automatic)")
                if !isSecondary, ProcessInfo.processInfo.arguments.contains("-SillSceneSetFixtureTwo") {
                    openWindow(id: "sill-session", value: UUID(uuidString: "00000000-0000-4000-8000-000000000029")!)
                }
            }
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
        let stored = recovery.bind(windowID, to: scene)
        if !ready, seed == nil, VisionWorkspace.decode(workspace) == nil, let stored {
            workspace = stored.workspace.encoded
            preferences = stored.preferences
        }
        #if DEBUG
        if VisionSceneSetRecovery.fixture, VisionWorkspace.decode(workspace) == nil {
            workspace = VisionWorkspace(macID: "synthetic-scene-set", width: 1200, height: 800).encoded
            if isSecondary { preferences = .init(toolbarAutomatic: false, mouseMode: true, textScale: 1.25) }
        }
        #endif
        ready = true
        save()
        recover(from: scene)
    }
    private func save() {
        guard !isSecondary || windowID != nil, let scene = owningScene.value,
              let value = VisionWorkspace.decode(workspace) else { return }
        VisionSceneSetRecovery.shared.save(windowID, session: scene.session.persistentIdentifier,
                                           workspace: value, preferences: preferences)
    }
    private func recover(from scene: UIWindowScene) {
        let action = openWindow
        VisionSceneSetRecovery.shared.recover(from: scene) { id in
            if let id { action(id: "sill-session", value: id) }
            else { action(id: "sill-main") }
        }
    }
}
