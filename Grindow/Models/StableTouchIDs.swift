import Foundation

/// Gives each finger a small integer ID that stays the same for as long as it
/// touches the pad. AppKit identifies touches with opaque `NSTouch.identity`
/// objects; `ThreeFingerSwipeRecognizer` wants stable `Int32`s.
struct StableTouchIDs<Key: Hashable> {
    private var ids: [Key: Int32] = [:]
    private var next: Int32 = 1

    /// IDs for this frame's fingers, in order. Fingers absent from the frame
    /// are forgotten, so a finger that lifts and lands again gets a new ID.
    mutating func ids(for keys: [Key]) -> [Int32] {
        let present = Set(keys)
        ids = ids.filter { present.contains($0.key) }
        return keys.map { key in
            if let id = ids[key] { return id }
            let id = next
            next = next == .max ? 1 : next + 1
            ids[key] = id
            return id
        }
    }

    mutating func reset() {
        ids.removeAll()
    }
}
