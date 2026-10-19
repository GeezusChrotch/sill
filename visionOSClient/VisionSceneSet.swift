import Foundation

struct VisionScenePreferences: Codable, Equatable {
    var toolbarAutomatic = true
    var mouseMode = false
    var textScale = 0.0
    var isValid: Bool { textScale.isFinite && textScale >= 0 && textScale <= 8 }
}

/// A small credential-free recovery journal. Native SceneStorage remains authoritative when
/// available; this survives a whole-process exit even if visionOS recreates only one scene.
struct VisionSceneSet: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var windowID: UUID? // nil is the app's existing default/primary scene.
        var sessionID: String
        var workspace: VisionWorkspace
        var preferences = VisionScenePreferences()
        var key: String { windowID?.uuidString ?? "primary" }
    }
    var version = 1
    private(set) var entries: [Entry] = []
    static let limit = 4
    static let storageKey = "Sill.spatialSceneSet.v1"
    static func key(_ id: UUID?) -> String { id?.uuidString ?? "primary" }
    func entry(_ id: UUID?) -> Entry? { entries.first { $0.key == Self.key(id) } }
    mutating func upsert(_ entry: Entry) {
        guard entry.preferences.isValid, VisionWorkspace.decode(entry.workspace.encoded) != nil,
              entry.sessionID.utf8.count <= 256,
              entry.sessionID.isEmpty || !entries.contains(where: { $0.key != entry.key && $0.sessionID == entry.sessionID }) else { return }
        if let index = entries.firstIndex(where: { $0.key == entry.key }) { entries[index] = entry }
        else if entries.count < Self.limit { entries.append(entry) }
    }
    mutating func remove(_ id: UUID?) { entries.removeAll { $0.key == Self.key(id) } }
    mutating func retainMacs(_ admitted: Set<String>) { entries.removeAll { !admitted.contains($0.workspace.macID) } }
    @discardableResult
    mutating func discard(_ sessions: Set<String>, launchSessions: [String: String] = [:]) -> Bool {
        let identified = Set(entries.map(\.sessionID).filter { !$0.isEmpty })
        // A whole-set native discard (for example Close App/force quit) retires native handles,
        // while preserving logical workspaces. A subset is an individually closed window.
        let currentWholeSet = identified.count == entries.count && !identified.isEmpty && identified.isSubset(of: sessions)
        let launchIDs = entries.compactMap { launchSessions[$0.key] }.filter { !$0.isEmpty }
        let launchWholeSet = launchIDs.count == entries.count && !launchIDs.isEmpty && Set(launchIDs).isSubset(of: sessions)
        if currentWholeSet || launchWholeSet {
            for index in entries.indices where sessions.contains(entries[index].sessionID) { entries[index].sessionID = "" }
        } else { entries.removeAll { !$0.sessionID.isEmpty && sessions.contains($0.sessionID) } }
        return currentWholeSet || launchWholeSet
    }
    static func decode(_ text: String?) -> Self {
        guard let text, text.utf8.count <= 20_480, let data = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Self.self, from: data), value.version == 1,
              value.entries.count <= limit, Set(value.entries.map(\.key)).count == value.entries.count,
              Set(value.entries.map(\.sessionID).filter { !$0.isEmpty }).count == value.entries.filter({ !$0.sessionID.isEmpty }).count,
              value.entries.allSatisfy({ $0.sessionID.utf8.count <= 256 && $0.preferences.isValid && VisionWorkspace.decode($0.workspace.encoded) != nil }) else { return Self() }
        return value
    }
    var encoded: String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}

/// Process-local replay gate. Cancellation permanently ends this launch's replay; a new process
/// creates a fresh gate. Native UUID presentation supplies identity deduplication across launches.
struct VisionSceneReplay {
    private(set) var started = false
    private(set) var cancelled = false
    private(set) var requested = Set<String>()
    mutating func start() -> Bool {
        guard !started else { return false }
        started = true
        return true
    }
    mutating func cancel() { cancelled = true }
    mutating func resetAfterConfirmedClosure() { self = Self() }
    mutating func claim(_ entry: VisionSceneSet.Entry, in journal: VisionSceneSet, bound: Set<String>) -> Bool {
        guard started, !cancelled, journal.entry(entry.windowID) == entry,
              !bound.contains(entry.key), !requested.contains(entry.key) else { return false }
        requested.insert(entry.key)
        return true
    }
}

/// Native-session ownership fences late view updates after a permanent discard. Rebinding the
/// same logical UUID with a new native session is allowed; an old view cannot re-enrol itself.
struct VisionSceneBindings {
    private(set) var sessions: [String: String] = [:]
    private var retired = Set<String>()
    mutating func bind(_ key: String, session: String) -> Bool {
        guard !retired.contains(session), !sessions.contains(where: { $0.key != key && $0.value == session }) else { return false }
        sessions[key] = session
        return true
    }
    func owns(_ key: String, session: String) -> Bool { sessions[key] == session }
    mutating func discard(_ ids: Set<String>) {
        retired.formUnion(ids)
        sessions = sessions.filter { !ids.contains($0.value) }
    }
    mutating func disconnect(_ session: String) { sessions = sessions.filter { $0.value != session } }
}

#if os(visionOS)
import SwiftUI
import UIKit

private struct SpatialScenePreferencesKey: EnvironmentKey {
    static let defaultValue: Binding<VisionScenePreferences>? = nil
}
private struct SpatialSceneIDKey: EnvironmentKey { static let defaultValue: UUID? = nil }
private struct SpatialNativeSessionKey: EnvironmentKey { static let defaultValue: String? = nil }
extension EnvironmentValues {
    var spatialScenePreferences: Binding<VisionScenePreferences>? {
        get { self[SpatialScenePreferencesKey.self] }
        set { self[SpatialScenePreferencesKey.self] = newValue }
    }
    var spatialNativeSession: String? {
        get { self[SpatialNativeSessionKey.self] }
        set { self[SpatialNativeSessionKey.self] = newValue }
    }
    var spatialSceneID: UUID? {
        get { self[SpatialSceneIDKey.self] }
        set { self[SpatialSceneIDKey.self] = newValue }
    }
}

@MainActor
final class VisionSceneSetRecovery {
    static let shared = VisionSceneSetRecovery()
    private var journal: VisionSceneSet
    private var bindings = VisionSceneBindings()
    private var launchSessions: [String: String] = [:]
    private var recoveryOwner: String?
    private var replay = VisionSceneReplay()
    private var recovery: Task<Void, Never>?
    private var generation = UUID()
    private var observer: NSObjectProtocol?

    #if DEBUG
    static var fixture: Bool { ProcessInfo.processInfo.arguments.contains("-SillSceneSetFixture") }
    #else
    static var fixture: Bool { false }
    #endif

    private init() {
        journal = VisionSceneSet.decode(UserDefaults.standard.string(forKey: VisionSceneSet.storageKey))
        observer = NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
            guard let scene = note.object as? UIWindowScene else { return }
            MainActor.assumeIsolated {
                self?.bindings.disconnect(scene.session.persistentIdentifier)
                // Only the scene that owns the delayed action can cancel its replay.
                if self?.recoveryOwner == scene.session.persistentIdentifier { self?.cancelRecovery() }
                if self?.bindings.sessions.isEmpty == true { self?.resetAfterClosure() }
            }
        }
        pruneTrust()
        launchSessions = Dictionary(uniqueKeysWithValues: journal.entries.map { ($0.key, $0.sessionID) })
    }
    private func persist() { UserDefaults.standard.set(journal.encoded, forKey: VisionSceneSet.storageKey) }
    private func pruneTrust() {
        guard !Self.fixture else { return }
        let admitted = DeviceIdentity.existing() == nil ? [] : SavedMacs.decode(UserDefaults.standard.string(forKey: SavedMacs.defaultsKey)).filter {
            $0.revoked != true && $0.newKey != true && $0.fingerprintData != nil
        }.map(\.macID)
        journal.retainMacs(Set(admitted)); persist()
    }
    func bind(_ id: UUID?, to scene: UIWindowScene) -> VisionSceneSet.Entry? {
        let sessionID = scene.session.persistentIdentifier
        guard bindings.bind(VisionSceneSet.key(id), session: sessionID) else { return nil }
        if var entry = journal.entry(id) {
            entry.sessionID = sessionID; journal.upsert(entry); persist()
            return entry
        }
        return nil
    }
    func save(_ id: UUID?, session: String, workspace: VisionWorkspace, preferences: VisionScenePreferences) {
        guard bindings.owns(VisionSceneSet.key(id), session: session) else { return }
        journal.upsert(.init(windowID: id, sessionID: session, workspace: workspace, preferences: preferences)); persist()
    }
    func clear(_ id: UUID?, session: String) {
        guard bindings.owns(VisionSceneSet.key(id), session: session) else { return }
        cancelRecovery(); journal.remove(id); persist()
    }
    func prune(admitted: Set<String>) {
        journal.retainMacs(admitted); persist()
    }
    func discard(_ sessions: Set<String>) {
        bindings.discard(sessions)
        let wholeSet = journal.discard(sessions, launchSessions: launchSessions)
        if wholeSet, bindings.sessions.isEmpty { resetAfterClosure() }
        persist()
    }
    private func resetAfterClosure() {
        cancelRecovery()
        replay.resetAfterConfirmedClosure()
        recoveryOwner = nil
    }
    private func cancelRecovery() {
        replay.cancel()
        generation = UUID(); recovery?.cancel(); recovery = nil
    }
    func recover(from scene: UIWindowScene, open: @escaping (UUID?) -> Void) {
        guard replay.start() else { return }
        recoveryOwner = scene.session.persistentIdentifier
        let token = generation
        recovery = Task { @MainActor [weak self, weak scene] in
            // Allow UIKit's launch-time permanent-discard callback and native scene binding first.
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            guard let self, let scene, !Task.isCancelled, token == self.generation,
                  scene.activationState == .foregroundActive else { return }
            let entries = self.journal.entries
            #if DEBUG
            print("SCENE_SET recover saved=\(entries.count) bound=\(self.bindings.sessions.count)")
            #endif
            for entry in entries {
                guard !Task.isCancelled, token == self.generation,
                      self.journal.entry(entry.windowID) != nil else { return }
                if !self.replay.claim(entry, in: self.journal, bound: Set(self.bindings.sessions.keys)) { continue }
                // An archived native primary has no typed UUID. Activate it instead of making
                // an extra default WindowGroup instance. Typed UUIDs already deduplicate natively.
                if entry.windowID == nil, let existing = UIApplication.shared.openSessions.first(where: { $0.persistentIdentifier == entry.sessionID }) {
                    UIApplication.shared.requestSceneSessionActivation(existing, userActivity: nil, options: nil) { error in
                        #if DEBUG
                        print("SCENE_SET primary activation declined code=\((error as NSError).code)")
                        #endif
                    }
                } else { open(entry.windowID) }
            }
            self.recovery = nil
        }
    }
    #if DEBUG
    func seedFixture() {
        let id = UUID(uuidString: "00000000-0000-4000-8000-000000000029")!
        guard journal.entries.isEmpty else { return }
        let workspace = VisionWorkspace(macID: "synthetic-scene-set", width: 1200, height: 800)
        journal.upsert(.init(windowID: nil, sessionID: "", workspace: workspace))
        journal.upsert(.init(windowID: id, sessionID: "", workspace: workspace,
                             preferences: .init(toolbarAutomatic: false, mouseMode: true, textScale: 1.25)))
        persist()
    }
    #endif
}

final class VisionSceneSetAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        VisionSceneSetRecovery.shared.discard(Set(sceneSessions.map(\.persistentIdentifier)))
    }
}

/// Bind the native session before starting a network client or using a ledger fallback.
struct VisionSceneSetBinding: UIViewRepresentable {
    var onBind: (UIWindowScene) -> Void
    func makeUIView(context: Context) -> BindingView { BindingView() }
    func updateUIView(_ view: BindingView, context: Context) { view.onBind = onBind; view.bind() }
    final class BindingView: UIView {
        var onBind: ((UIWindowScene) -> Void)?
        private var delivered: String?
        override func didMoveToWindow() { super.didMoveToWindow(); bind() }
        func bind() {
            guard let scene = window?.windowScene, delivered != scene.session.persistentIdentifier, let onBind else { return }
            delivered = scene.session.persistentIdentifier
            DispatchQueue.main.async { [weak self, weak scene] in
                guard let self, let scene, self.window?.windowScene === scene,
                      self.delivered == scene.session.persistentIdentifier else { return }
                onBind(scene)
            }
        }
    }
}
#endif
