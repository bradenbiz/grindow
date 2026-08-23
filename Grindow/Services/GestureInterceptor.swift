import Cocoa
import CoreGraphics

// MARK: - Private MultitouchSupport.framework bindings

private typealias MTDeviceRef = UnsafeMutableRawPointer

private struct MTReadout {
    var posX: Float
    var posY: Float
    var velX: Float
    var velY: Float
}

private struct MTTouch {
    var frame: Int32
    var _pad0: Int32   // explicit pad to align `timestamp` (Double) at offset 8
    var timestamp: Double
    var identifier: Int32
    var state: Int32   // 1=not touching, 4=touching, 6/7=lifted
    var fingerIdx: Int32
    var handIdx: Int32
    var normalized: MTReadout       // 16 bytes, components in [0,1]
    var size: Float
    var reserved1: Int32
    var angle: Float
    var majorAxis: Float
    var minorAxis: Float
    var absolute: MTReadout         // 16 bytes, in display points
    var reserved2: Int32
    var reserved3: Int32
    var zDensity: Float
}

// Callback takes a raw pointer because @convention(c) requires Obj-C-representable
// parameters, and `UnsafeMutablePointer<MTTouch>` isn't. We rebind inside.
private typealias MTContactFrameCallback = @convention(c) (
    Int32,
    UnsafeMutableRawPointer?,
    Int32,
    Double,
    Int32
) -> Int32

@_silgen_name("MTDeviceCreateDefault")
private func MTDeviceCreateDefault() -> MTDeviceRef?

@_silgen_name("MTRegisterContactFrameCallback")
private func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactFrameCallback)

@_silgen_name("MTUnregisterContactFrameCallback")
private func MTUnregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactFrameCallback)

@_silgen_name("MTDeviceStart")
private func MTDeviceStart(_ device: MTDeviceRef, _ flags: Int32) -> Int32

@_silgen_name("MTDeviceStop")
private func MTDeviceStop(_ device: MTDeviceRef) -> Int32

@_silgen_name("MTDeviceRelease")
private func MTDeviceRelease(_ device: MTDeviceRef)

// MARK: - C callback (cannot capture)

private let multitouchCallback: MTContactFrameCallback = { _, rawPtr, nTouches, timestamp, frame in
    guard let rawPtr = rawPtr, nTouches > 0 else { return 0 }
    let typedPtr = rawPtr.assumingMemoryBound(to: MTTouch.self)
    let buffer = UnsafeBufferPointer(start: typedPtr, count: Int(nTouches))
    let touches = Array(buffer)
    DispatchQueue.main.async {
        GestureInterceptor.shared.handleTouchFrame(touches: touches, timestamp: timestamp, frame: frame)
    }
    return 0
}

// MARK: - GestureInterceptor

/// Intercepts three-finger trackpad swipe gestures using the private
/// `MultitouchSupport.framework`. Reads raw finger positions before macOS's
/// gesture recognizer routes vertical swipes to Mission Control / Exposé.
///
/// Note: this only *detects* swipes — macOS still acts on its built-in
/// three-finger gestures unless the user disables them in
/// System Settings → Trackpad → More Gestures.
class GestureInterceptor: ObservableObject {
    static let shared = GestureInterceptor()

    @Published var isActive: Bool = false

    /// Called when a three-finger swipe is detected in any of the four directions.
    var onSwipe: ((SwipeDirection) -> Void)?

    // MARK: - Tunables

    private let minFingerCount: Int = 3
    /// Minimum |Δ| (in normalized [0,1] pad coords) before a swipe fires.
    private let minAxialDelta: Float = 0.08
    /// Dominant axis must exceed the other by this factor.
    private let minAxialDominance: Float = 1.5

    // MARK: - State (main queue only)

    private var device: MTDeviceRef?
    private var isTracking: Bool = false
    private var swipeEmittedForCurrentGesture: Bool = false
    private var startPositions: [Int32: (x: Float, y: Float)] = [:]
    private var currentPositions: [Int32: (x: Float, y: Float)] = [:]
    private var activeFingerIds: Set<Int32> = []

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard device == nil else { return }

        let size = MemoryLayout<MTTouch>.size
        guard size == 96 else {
            print("Grindow: MTTouch struct size = \(size), expected 96. Aborting — layout mismatch would corrupt finger reads.")
            return
        }

        guard let dev = MTDeviceCreateDefault() else {
            print("Grindow: MTDeviceCreateDefault returned nil — no multitouch device available.")
            return
        }

        MTRegisterContactFrameCallback(dev, multitouchCallback)
        let result = MTDeviceStart(dev, 0)
        guard result == 0 else {
            print("Grindow: MTDeviceStart failed (\(result))")
            MTUnregisterContactFrameCallback(dev, multitouchCallback)
            MTDeviceRelease(dev)
            return
        }

        device = dev
        isActive = true
        print("Grindow: Gesture interceptor started (MultitouchSupport)")
    }

    func stop() {
        guard let dev = device else { return }
        _ = MTDeviceStop(dev)
        MTUnregisterContactFrameCallback(dev, multitouchCallback)
        MTDeviceRelease(dev)
        device = nil
        resetTracking()
        isActive = false
        print("Grindow: Gesture interceptor stopped")
    }

    // MARK: - Frame handling

    fileprivate func handleTouchFrame(touches: [MTTouch], timestamp: Double, frame: Int32) {
        let inContact = touches.filter { $0.state == 4 }

        guard inContact.count >= minFingerCount else {
            if isTracking { resetTracking() }
            return
        }

        let ids = Set(inContact.map { $0.identifier })

        if !isTracking {
            beginTracking(touches: inContact, ids: ids)
            return
        }

        // Finger composition changed mid-gesture — reset to avoid stale deltas.
        if ids != activeFingerIds {
            resetTracking()
            beginTracking(touches: inContact, ids: ids)
            return
        }

        for t in inContact {
            currentPositions[t.identifier] = (t.normalized.posX, t.normalized.posY)
        }

        if !swipeEmittedForCurrentGesture {
            checkForSwipe()
        }
    }

    private func beginTracking(touches: [MTTouch], ids: Set<Int32>) {
        isTracking = true
        swipeEmittedForCurrentGesture = false
        activeFingerIds = ids
        startPositions.removeAll(keepingCapacity: true)
        currentPositions.removeAll(keepingCapacity: true)
        for t in touches {
            startPositions[t.identifier] = (t.normalized.posX, t.normalized.posY)
            currentPositions[t.identifier] = (t.normalized.posX, t.normalized.posY)
        }
    }

    private func resetTracking() {
        isTracking = false
        swipeEmittedForCurrentGesture = false
        activeFingerIds.removeAll()
        startPositions.removeAll(keepingCapacity: true)
        currentPositions.removeAll(keepingCapacity: true)
    }

    private func checkForSwipe() {
        guard !startPositions.isEmpty else { return }

        var sumDX: Float = 0
        var sumDY: Float = 0
        var count: Float = 0
        for (id, start) in startPositions {
            guard let cur = currentPositions[id] else { continue }
            sumDX += cur.x - start.x
            sumDY += cur.y - start.y
            count += 1
        }
        guard count > 0 else { return }

        let avgDX = sumDX / count
        let avgDY = sumDY / count
        let absDX = abs(avgDX)
        let absDY = abs(avgDY)

        // Pick the dominant axis. If neither axis has enough travel, or neither
        // dominates the other, don't emit.
        let direction: SwipeDirection
        if absDY >= minAxialDelta && absDY >= absDX * minAxialDominance {
            // MT normalized coords: y=0 is near the user, y=1 is far.
            // Fingers moving away from the user → avgDY > 0 → swipe up.
            var d: SwipeDirection = avgDY > 0 ? .up : .down
            if AppSettings.shared.invertVerticalSwipe {
                d = (d == .up) ? .down : .up
            }
            direction = d
        } else if absDX >= minAxialDelta && absDX >= absDY * minAxialDominance {
            // MT normalized coords: x=0 is left, x=1 is right.
            // Fingers moving right → avgDX > 0 → swipe right.
            direction = avgDX > 0 ? .right : .left
        } else {
            return
        }

        swipeEmittedForCurrentGesture = true
        onSwipe?(direction)
    }
}
