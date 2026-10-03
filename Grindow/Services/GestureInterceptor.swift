import Cocoa
import CoreGraphics
import IOKit

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

@_silgen_name("MTDeviceCreateList")
private func MTDeviceCreateList() -> UnsafeMutableRawPointer?   // +1 CFArray of MTDeviceRef

@_silgen_name("MTRegisterContactFrameCallback")
private func MTRegisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactFrameCallback)

@_silgen_name("MTUnregisterContactFrameCallback")
private func MTUnregisterContactFrameCallback(_ device: MTDeviceRef, _ callback: MTContactFrameCallback)

@_silgen_name("MTDeviceStart")
private func MTDeviceStart(_ device: MTDeviceRef, _ flags: Int32) -> Int32

@_silgen_name("MTDeviceStop")
private func MTDeviceStop(_ device: MTDeviceRef) -> Int32

// MARK: - C callbacks (cannot capture)

/// In-contact count of the last frame forwarded to the main queue. The
/// callback runs on MultitouchSupport's thread at ~90-120 Hz, so frames that
/// neither have the tracked finger count nor change the count (ordinary
/// pointing and scrolling) are dropped here instead of being copied and
/// dispatched.
private let forwardedCountLock = NSLock()
private var lastForwardedCount = -1

private let multitouchCallback: MTContactFrameCallback = { _, rawPtr, nTouches, _, _ in
    let count = rawPtr == nil ? 0 : Int(max(0, nTouches))
    let touches = UnsafeBufferPointer<MTTouch>(
        start: rawPtr.map { UnsafePointer($0.assumingMemoryBound(to: MTTouch.self)) }, count: count)
    let inContact = touches.reduce(0) { $0 + ($1.state == 4 ? 1 : 0) }

    forwardedCountLock.lock()
    let changed = inContact != lastForwardedCount
    lastForwardedCount = inContact
    forwardedCountLock.unlock()
    guard changed || inContact == GestureInterceptor.trackedFingerCount else { return 0 }

    let contacts = touches.filter { $0.state == 4 }
    DispatchQueue.main.async { GestureInterceptor.shared.handleTouchFrame(contacts: contacts) }
    return 0
}

/// Fires on the main run loop when a multitouch device appears or disappears.
private let deviceHotplugCallback: IOServiceMatchingCallback = { _, iterator in
    drainIterator(iterator)
    GestureInterceptor.shared.scheduleReattach()
}

/// Releases every matched service; this also re-arms the notification.
private func drainIterator(_ iterator: io_iterator_t) {
    while case let service = IOIteratorNext(iterator), service != 0 {
        IOObjectRelease(service)
    }
}

// MARK: - GestureInterceptor

/// Intercepts three-finger trackpad swipe gestures using the private
/// `MultitouchSupport.framework`. Reads raw finger positions before macOS's
/// gesture recognizer routes vertical swipes to Mission Control / Exposé.
///
/// Note: this only *detects* swipes — macOS still acts on its built-in
/// three-finger gestures unless the user disables them in
/// System Settings → Trackpad → More Gestures. `NativeTrackpadGestures`
/// reports when that is the case so callers can avoid a double switch.
class GestureInterceptor: ObservableObject {
    static let shared = GestureInterceptor()

    @Published var isActive: Bool = false

    /// Called when a three-finger swipe is detected in any of the four directions.
    var onGestureBegan: (() -> Void)?
    var onSwipe: ((SwipeDirection) -> Void)?

    // MARK: - Tunables

    fileprivate static let trackedFingerCount: Int = 3
    /// Minimum |Δ| (in normalized [0,1] pad coords) before a swipe fires.
    private let minAxialDelta: Float = 0.08
    /// Dominant axis must exceed the other by this factor.
    private let minAxialDominance: Float = 1.5

    // MARK: - State (main queue only)

    /// Keeps the devices returned by `MTDeviceCreateList` alive while started.
    private var deviceList: CFArray?
    private var devices: [MTDeviceRef] = []
    /// Whether the app wants gestures on; device changes re-attach only then.
    private var wanted = false
    private var wakeObserver: NSObjectProtocol?
    private var notificationPort: IONotificationPortRef?
    private var hotplugIterators: [io_iterator_t] = []
    private var reattachWork: DispatchWorkItem?

    private var isTracking: Bool = false
    private var swipeEmittedForCurrentGesture: Bool = false
    /// Set once more fingers than tracked touch down; cleared only when every
    /// finger lifts, so a four-finger gesture never becomes a three-finger one
    /// while fingers land or lift at slightly different times.
    private var gestureHadExtraFingers: Bool = false
    private var startPositions: [Int32: (x: Float, y: Float)] = [:]
    private var currentPositions: [Int32: (x: Float, y: Float)] = [:]
    private var activeFingerIds: Set<Int32> = []

    private init() {}

    // MARK: - Start / Stop

    func start() {
        wanted = true
        installDeviceWatchers()
        if devices.isEmpty { attachDevices() }
    }

    func stop() {
        wanted = false
        reattachWork?.cancel()
        reattachWork = nil
        detachDevices()
        print("Grindow: Gesture interceptor stopped")
    }

    /// Re-creates the device list after wake or a trackpad being connected or
    /// disconnected. Debounced: devices can take a moment to come back.
    fileprivate func scheduleReattach() {
        reattachWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.wanted else { return }
            self.detachDevices()
            self.attachDevices()
        }
        reattachWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func attachDevices() {
        let size = MemoryLayout<MTTouch>.size
        guard size == 96 else {
            print("Grindow: MTTouch struct size = \(size), expected 96. Aborting — layout mismatch would corrupt finger reads.")
            return
        }

        guard let raw = MTDeviceCreateList() else {
            print("Grindow: MTDeviceCreateList returned nil — no multitouch device available.")
            return
        }
        let list = Unmanaged<CFArray>.fromOpaque(raw).takeRetainedValue()

        forwardedCountLock.lock()
        lastForwardedCount = -1
        forwardedCountLock.unlock()

        var started: [MTDeviceRef] = []
        for index in 0..<CFArrayGetCount(list) {
            guard let value = CFArrayGetValueAtIndex(list, index) else { continue }
            let dev = UnsafeMutableRawPointer(mutating: value)
            MTRegisterContactFrameCallback(dev, multitouchCallback)
            let result = MTDeviceStart(dev, 0)
            if result == 0 {
                started.append(dev)
            } else {
                print("Grindow: MTDeviceStart failed (\(result))")
                MTUnregisterContactFrameCallback(dev, multitouchCallback)
            }
        }

        deviceList = list
        devices = started
        isActive = !started.isEmpty
        print("Grindow: Gesture interceptor started on \(started.count) multitouch device(s)")
    }

    private func detachDevices() {
        for dev in devices {
            MTUnregisterContactFrameCallback(dev, multitouchCallback)
            _ = MTDeviceStop(dev)
        }
        devices = []
        deviceList = nil   // releases the devices
        resetTracking()
        gestureHadExtraFingers = false
        isActive = false
    }

    private func installDeviceWatchers() {
        guard wakeObserver == nil else { return }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.scheduleReattach() }

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port
        CFRunLoopAddSource(CFRunLoopGetMain(), IONotificationPortGetRunLoopSource(port).takeUnretainedValue(), .defaultMode)
        for type in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            guard IOServiceAddMatchingNotification(port, type, IOServiceMatching("AppleMultitouchDevice"),
                                                   deviceHotplugCallback, nil, &iterator) == KERN_SUCCESS else { continue }
            // Devices already present are attached by start(); draining arms the notification.
            drainIterator(iterator)
            hotplugIterators.append(iterator)
        }
    }

    // MARK: - Frame handling

    fileprivate func handleTouchFrame(contacts inContact: [MTTouch]) {
        guard !devices.isEmpty else { return }

        if inContact.isEmpty {
            gestureHadExtraFingers = false
        } else if inContact.count > Self.trackedFingerCount {
            gestureHadExtraFingers = true
        }

        guard inContact.count == Self.trackedFingerCount, !gestureHadExtraFingers else {
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
        onGestureBegan?()
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
            direction = avgDY > 0 ? .up : .down
        } else if absDX >= minAxialDelta && absDX >= absDY * minAxialDominance {
            // MT normalized coords: x=0 is left, x=1 is right.
            // Fingers moving right → avgDX > 0 → swipe right.
            direction = avgDX > 0 ? .right : .left
        } else {
            return
        }

        swipeEmittedForCurrentGesture = true
        onSwipe?(AppSettings.shared.invertSwipes ? direction.reversed : direction)
    }
}

// MARK: - Native trackpad gestures

/// Reads macOS's trackpad preferences to see whether the system also acts on
/// three-finger swipes along an axis. When it does, macOS and Grindow would
/// both switch Spaces on the same swipe.
enum NativeTrackpadGestures {
    /// Built-in trackpad first, then Magic Trackpad; System Settings writes both.
    private static let domains = [
        "com.apple.AppleMultitouchTrackpad",
        "com.apple.driver.AppleBluetoothMultitouch.trackpad"
    ]

    /// "Swipe between full-screen apps" is set to three fingers.
    static var claimsHorizontalSwipes: Bool { value(for: "TrackpadThreeFingerHorizSwipeGesture") != 0 }

    /// Mission Control / App Exposé are set to three fingers.
    static var claimsVerticalSwipes: Bool { value(for: "TrackpadThreeFingerVertSwipeGesture") != 0 }

    static func claims(_ direction: SwipeDirection) -> Bool {
        switch direction {
        case .left, .right: return claimsHorizontalSwipes
        case .up, .down: return claimsVerticalSwipes
        }
    }

    private static func value(for key: String) -> Int {
        for domain in domains {
            // Pick up changes System Settings made after launch.
            CFPreferencesAppSynchronize(domain as CFString)
            if let number = CFPreferencesCopyAppValue(key as CFString, domain as CFString) as? NSNumber {
                return number.intValue
            }
        }
        return 2 // Unset means the macOS default: three fingers.
    }
}
