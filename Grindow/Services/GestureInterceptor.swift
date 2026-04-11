import Cocoa
import CoreGraphics

/// Intercepts three-finger trackpad swipe gestures using CGEventTap.
///
/// This class creates a system-level event tap that captures gesture events
/// before they reach the window server. It detects three-finger vertical swipes
/// and suppresses the default macOS behavior (Mission Control / App Exposé),
/// replacing them with Grindow's 2D grid navigation.
///
/// Horizontal three-finger swipes are passed through to macOS for normal
/// Space switching behavior.
class GestureInterceptor: ObservableObject {
    static let shared = GestureInterceptor()

    @Published var isActive: Bool = false

    /// Called when a vertical swipe is detected. The parameter is the direction.
    var onSwipe: ((SwipeDirection) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Gesture tracking state
    private var touchCount: Int = 0
    private var gesturePhase: GesturePhase = .none
    private var accumulatedDeltaX: CGFloat = 0
    private var accumulatedDeltaY: CGFloat = 0

    // Thresholds for swipe detection
    private let swipeThreshold: CGFloat = 0.4
    private let directionLockRatio: CGFloat = 1.5 // Y must be 1.5x X to count as vertical

    private enum GesturePhase {
        case none
        case tracking
        case horizontalLocked  // Horizontal swipe detected, pass through
        case verticalLocked    // Vertical swipe detected, we handle it
        case completed
    }

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard eventTap == nil else { return }

        // We need to intercept gesture events (type 29) and possibly scroll events.
        // NSEvent.EventType.gesture = 29
        // NSEvent.EventType.swipe = 31
        // We also capture scroll wheel events since macOS sometimes routes
        // three-finger swipes through the scroll system.

        let eventMask: CGEventMask = (
            (1 << 29) |           // kCGEventGesture (NSEvent.EventType.gesture.rawValue)
            (1 << 31) |           // NSEvent.EventType.swipe
            (1 << CGEventType.scrollWheel.rawValue)
        )

        // Create the event tap
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: gestureEventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Grindow: Failed to create event tap. Ensure Accessibility permissions are granted.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        print("Grindow: Gesture interceptor started")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isActive = false
        resetGestureState()
        print("Grindow: Gesture interceptor stopped")
    }

    // MARK: - Gesture State

    func resetGestureState() {
        gesturePhase = .none
        accumulatedDeltaX = 0
        accumulatedDeltaY = 0
        touchCount = 0
    }

    // MARK: - Event Processing

    /// Processes a CGEvent and returns nil to suppress it or the event to pass through.
    func processEvent(_ event: CGEvent) -> CGEvent? {
        let eventType = event.type

        // Handle swipe events (type 31) — these are discrete swipe notifications
        if eventType.rawValue == 31 {
            return handleSwipeEvent(event)
        }

        // Handle gesture events (type 29) — these are continuous gesture tracking
        if eventType.rawValue == 29 {
            return handleGestureEvent(event)
        }

        // Handle scroll wheel events that might be three-finger swipes
        if eventType == .scrollWheel {
            return handleScrollEvent(event)
        }

        return event
    }

    private func handleSwipeEvent(_ event: CGEvent) -> CGEvent? {
        guard let nsEvent = NSEvent(cgEvent: event) else { return event }

        // NSEvent.swipe provides deltaX/deltaY as -1, 0, or 1
        let dx = nsEvent.deltaX
        let dy = nsEvent.deltaY

        if abs(dy) > abs(dx) {
            // Vertical swipe detected
            let direction: SwipeDirection = dy > 0 ? .down : .up
            DispatchQueue.main.async { [weak self] in
                self?.onSwipe?(direction)
            }
            return nil  // Suppress the event
        }

        // Horizontal swipe — pass through to macOS
        return event
    }

    private func handleGestureEvent(_ event: CGEvent) -> CGEvent? {
        // Gesture events contain subtype and phase information.
        // We extract these from the event's integer fields.

        // CGEvent field 110 = gesture subtype
        // CGEvent field 132 = gesture phase (began=1, changed=2, ended=4)
        // CGEvent field 135 = touch count

        let subtype = event.getIntegerValueField(CGEventField(rawValue: 110)!)
        let phase = event.getIntegerValueField(CGEventField(rawValue: 132)!)
        let touches = event.getIntegerValueField(CGEventField(rawValue: 135)!)

        // We only care about three-finger gestures
        // Subtype 5 = swipe gesture, subtype 6 = scroll gesture with fingers
        guard touches == 3 || touchCount == 3 else {
            return event
        }

        touchCount = Int(touches)

        switch phase {
        case 1: // Began
            gesturePhase = .tracking
            accumulatedDeltaX = 0
            accumulatedDeltaY = 0
            return event  // Let begin pass through initially

        case 2: // Changed
            guard gesturePhase == .tracking || gesturePhase == .verticalLocked else {
                return gesturePhase == .horizontalLocked ? event : nil
            }

            // Extract deltas from the gesture event
            // Fields 116/119 contain the gesture delta values
            let dx = CGFloat(event.getDoubleValueField(CGEventField(rawValue: 116)!))
            let dy = CGFloat(event.getDoubleValueField(CGEventField(rawValue: 119)!))

            accumulatedDeltaX += dx
            accumulatedDeltaY += dy

            if gesturePhase == .tracking {
                // Determine direction lock once we have enough movement
                let totalMovement = sqrt(accumulatedDeltaX * accumulatedDeltaX + accumulatedDeltaY * accumulatedDeltaY)
                if totalMovement > 0.1 {
                    if abs(accumulatedDeltaY) > abs(accumulatedDeltaX) * directionLockRatio {
                        gesturePhase = .verticalLocked
                        return nil  // Start suppressing
                    } else {
                        gesturePhase = .horizontalLocked
                        return event  // Let horizontal pass through
                    }
                }
            }

            if gesturePhase == .verticalLocked {
                return nil  // Suppress vertical gesture events
            }

            return event

        case 4, 8: // Ended or Cancelled
            let wasVertical = gesturePhase == .verticalLocked

            if wasVertical {
                // Determine swipe direction from accumulated deltas
                if abs(accumulatedDeltaY) > swipeThreshold {
                    let direction: SwipeDirection = accumulatedDeltaY > 0 ? .down : .up
                    DispatchQueue.main.async { [weak self] in
                        self?.onSwipe?(direction)
                    }
                }
            }

            resetGestureState()
            return wasVertical ? nil : event

        default:
            return event
        }
    }

    private func handleScrollEvent(_ event: CGEvent) -> CGEvent? {
        // Three-finger swipes can also come through as momentum scroll events.
        // We check for the gesture scroll variant (non-pixel-aligned, phase-based).

        let phase = event.getIntegerValueField(.scrollWheelEventScrollPhase)
        let momentumPhase = event.getIntegerValueField(.scrollWheelEventMomentumPhase)

        // Only intercept gesture-phase scrolls (not momentum), and only
        // if we're actively tracking a three-finger gesture
        if momentumPhase != 0 || phase == 0 {
            return event  // Regular scroll or momentum — pass through
        }

        // Check if this is a three-finger scroll by examining the point data count
        let pointCount = event.getIntegerValueField(.scrollWheelEventPointDataCount)
        guard pointCount == 3 else {
            return event
        }

        let dy = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1)
        let dx = event.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2)

        // If primarily vertical, suppress and track
        if abs(dy) > abs(dx) * Double(directionLockRatio) && abs(dy) > 0.5 {
            let direction: SwipeDirection = dy > 0 ? .up : .down
            DispatchQueue.main.async { [weak self] in
                self?.onSwipe?(direction)
            }
            return nil
        }

        return event
    }
}

// MARK: - C Callback

/// The CGEventTap callback function. Must be a free C function.
private func gestureEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Re-enable the tap if it gets disabled (system can disable taps under load)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let interceptor = Unmanaged<GestureInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = interceptor.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let interceptor = Unmanaged<GestureInterceptor>.fromOpaque(userInfo).takeUnretainedValue()

    if let resultEvent = interceptor.processEvent(event) {
        return Unmanaged.passUnretained(resultEvent)
    }

    // Return nil to suppress the event
    return nil
}
