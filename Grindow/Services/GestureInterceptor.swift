import Cocoa
import CoreGraphics

// MARK: - Event tap callback (cannot capture)

private let gestureTapCallback: CGEventTapCallBack = { _, type, event, _ in
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        DispatchQueue.main.async { GestureInterceptor.shared.reenableTap() }
    default:
        GestureInterceptor.shared.handleGestureEvent(event)
    }
    return Unmanaged.passUnretained(event)
}

// MARK: - GestureInterceptor

/// Detects three-finger trackpad swipes with a listen-only `CGEventTap` on
/// gesture events, reading each finger from `NSEvent.allTouches()`. Public API
/// only (no MultitouchSupport); needs the Accessibility grant Grindow already
/// requires. The tap only listens, so every app still receives the touches.
///
/// Note: this only *detects* swipes — macOS still acts on its built-in
/// three-finger gestures unless the user disables them in
/// System Settings → Trackpad → More Gestures.
class GestureInterceptor: NSObject, ObservableObject {
    static let shared = GestureInterceptor()

    @Published var isActive: Bool = false

    /// Called when a three-finger swipe is detected in any of the four directions.
    var onGestureBegan: (() -> Void)?
    var onSwipe: ((SwipeDirection) -> Void)?

    // MARK: - State (main thread only; the tap runs on the main run loop)

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var recognizer = ThreeFingerSwipeRecognizer()
    private var touchIDs = StableTouchIDs<NSObject>()
    private let ownPID = Int64(getpid())

    private override init() {}

    // MARK: - Start / Stop

    func start() {
        guard tap == nil else { return }

        let mask = CGEventMask(1) << CGEventMask(NSEvent.EventType.gesture.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: gestureTapCallback,
            userInfo: nil
        ) else {
            print("Grindow: could not create the gesture event tap (Accessibility not granted?)")
            return
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            print("Grindow: could not create a run loop source for the gesture tap")
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        runLoopSource = source
        isActive = true
        print("Grindow: Gesture interceptor started (event tap)")
    }

    func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CFMachPortInvalidate(tap)
        self.tap = nil
        runLoopSource = nil
        recognizer.reset()
        touchIDs.reset()
        isActive = false
        print("Grindow: Gesture interceptor stopped")
    }

    /// macOS disables a tap whose callback runs too long; turn it back on.
    fileprivate func reenableTap() {
        guard let tap else { return }
        recognizer.reset()
        touchIDs.reset()
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    // MARK: - Event handling

    fileprivate func handleGestureEvent(_ cgEvent: CGEvent) {
        guard tap != nil else { return }
        // Grindow posts synthetic Dock-swipe gestures to switch Spaces. They carry
        // no fingers and would reset the recognizer mid-swipe, so skip our own.
        guard cgEvent.getIntegerValueField(.eventSourceUnixProcessID) != ownPID else { return }

        let touches: [NSTouch] = autoreleasepool {
            guard let event = NSEvent(cgEvent: cgEvent) else { return [] }
            return event.allTouches().filter { $0.phase.contains(.touching) }
        }
        let ids = touchIDs.ids(for: touches.map { $0.identity as! NSObject })
        let contacts = zip(ids, touches).map { id, touch in
            let point = touch.normalizedPosition
            return TouchPoint(id: id, x: Float(point.x), y: Float(point.y))
        }

        // Callbacks may post a burst of gestures; keep that out of the tap callback.
        if let event = recognizer.process(contacts) {
            DispatchQueue.main.async { self.deliver(event) }
        }
    }

    /// Hands a recognizer event to the app. Live frames and the debug
    /// injection below both come through here, so they share everything
    /// after recognition, including inversion.
    private func deliver(_ event: ThreeFingerSwipeRecognizer.Event) {
        switch event {
        case .began:
            onGestureBegan?()
        case .swipe(let direction):
            onSwipe?(AppSettings.shared.invertSwipes ? direction.reversed : direction)
        }
    }

    // MARK: - Debug swipe injection

    #if DEBUG
    /// Debug builds only: lets a script stand in for the trackpad, for testing
    /// in a VM, which has none. Post the distributed notification
    /// `com.grindow.debug.swipe` with `userInfo["direction"]` set to "up",
    /// "down", "left" or "right" (Scripts/vm/swipe.swift does this). Each one
    /// acts like a three-finger swipe the recognizer just saw: `.began`, then
    /// `.swipe`, before inversion. Works whether or not a trackpad was found,
    /// so it bypasses only the event tap and the recognizer.
    static let debugSwipeNotification = Notification.Name("com.grindow.debug.swipe")

    func startDebugSwipeInjection() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(debugSwipeReceived(_:)),
            name: Self.debugSwipeNotification,
            object: nil,
            // Grindow is a menu bar app and is rarely frontmost; the default
            // behavior would hold or coalesce notifications while inactive.
            suspensionBehavior: .deliverImmediately
        )
        swipeLog.log("debug swipe injection listening for \(Self.debugSwipeNotification.rawValue, privacy: .public)")
    }

    @objc private func debugSwipeReceived(_ note: Notification) {
        let raw = note.userInfo?["direction"] as? String
        let direction: SwipeDirection?
        switch raw {
        case "up": direction = .up
        case "down": direction = .down
        case "left": direction = .left
        case "right": direction = .right
        default: direction = nil
        }
        guard let direction else {
            swipeLog.log("debug swipe ignored, bad direction \(raw ?? "nil", privacy: .public)")
            return
        }
        swipeLog.log("debug swipe \(String(describing: direction), privacy: .public) received")
        DispatchQueue.main.async {
            self.deliver(.began)
            self.deliver(.swipe(direction))
        }
    }
    #endif
}
