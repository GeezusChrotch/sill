import Foundation

/// Deferred system Paste reads may finish after a session replacement. They belong only to
/// the connected session whose control was presented, never to the next Mac/session.
enum VisionSessionPolicy {
    static func acceptsCompletion(startedAt: Date?, currentAt: Date?, connected: Bool) -> Bool {
        connected && startedAt != nil && startedAt == currentAt
    }
}
