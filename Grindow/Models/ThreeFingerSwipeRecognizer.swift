import Foundation

/// One finger in contact with the trackpad, in MultitouchSupport's normalized
/// [0,1] pad coordinates: x=0 is left, y=0 is nearest the user.
struct TouchPoint: Equatable {
    let id: Int32
    let x: Float
    let y: Float
}

/// Turns per-frame finger contacts into at most one swipe per three-finger
/// gesture. Kept free of MultitouchSupport so it can be driven by scripted
/// frames in tests; `GestureInterceptor` feeds it live frames.
struct ThreeFingerSwipeRecognizer {
    enum Event: Equatable {
        /// Tracking started (or restarted after the fingers changed).
        case began
        /// Fingers travelled far enough along one axis. Not yet inverted.
        case swipe(SwipeDirection)
    }

    static let fingerCount = 3
    /// Minimum |Δ| (in normalized [0,1] pad coords) before a swipe fires.
    var minAxialDelta: Float = 0.08
    /// Dominant axis must exceed the other by this factor.
    var minAxialDominance: Float = 1.5

    private(set) var isTracking = false
    private var swipeEmittedForCurrentGesture = false
    private var startPositions: [Int32: (x: Float, y: Float)] = [:]
    private var currentPositions: [Int32: (x: Float, y: Float)] = [:]
    private var activeFingerIds: Set<Int32> = []

    /// Feed one frame of in-contact fingers.
    mutating func process(_ contacts: [TouchPoint]) -> Event? {
        guard contacts.count == Self.fingerCount else {
            if isTracking { reset() }
            return nil
        }

        let ids = Set(contacts.map(\.id))

        // First frame, or finger composition changed mid-gesture: restart so
        // deltas aren't measured against another finger's start position.
        if !isTracking || ids != activeFingerIds {
            begin(contacts, ids: ids)
            return .began
        }

        for contact in contacts {
            currentPositions[contact.id] = (contact.x, contact.y)
        }

        guard !swipeEmittedForCurrentGesture, let direction = detectedDirection() else { return nil }
        swipeEmittedForCurrentGesture = true
        return .swipe(direction)
    }

    mutating func reset() {
        isTracking = false
        swipeEmittedForCurrentGesture = false
        activeFingerIds.removeAll()
        startPositions.removeAll(keepingCapacity: true)
        currentPositions.removeAll(keepingCapacity: true)
    }

    private mutating func begin(_ contacts: [TouchPoint], ids: Set<Int32>) {
        reset()
        isTracking = true
        activeFingerIds = ids
        for contact in contacts {
            startPositions[contact.id] = (contact.x, contact.y)
            currentPositions[contact.id] = (contact.x, contact.y)
        }
    }

    private func detectedDirection() -> SwipeDirection? {
        var sumDX: Float = 0
        var sumDY: Float = 0
        var count: Float = 0
        for (id, start) in startPositions {
            guard let current = currentPositions[id] else { continue }
            sumDX += current.x - start.x
            sumDY += current.y - start.y
            count += 1
        }
        guard count > 0 else { return nil }

        let avgDX = sumDX / count
        let avgDY = sumDY / count
        let absDX = abs(avgDX)
        let absDY = abs(avgDY)

        // Pick the dominant axis. If neither axis has enough travel, or neither
        // dominates the other, don't emit.
        if absDY >= minAxialDelta && absDY >= absDX * minAxialDominance {
            // Fingers moving away from the user → avgDY > 0 → swipe up.
            return avgDY > 0 ? .up : .down
        }
        if absDX >= minAxialDelta && absDX >= absDY * minAxialDominance {
            // Fingers moving right → avgDX > 0 → swipe right.
            return avgDX > 0 ? .right : .left
        }
        return nil
    }
}
