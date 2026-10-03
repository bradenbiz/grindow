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
    guard nTouches > 0, let rawPtr else {
        DispatchQueue.main.async { GestureInterceptor.shared.handleTouchFrame(touches: [], timestamp: timestamp, frame: frame) }
        return 0
    }
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
    var onGestureBegan: (() -> Void)?
    var onSwipe: ((SwipeDirection) -> Void)?

    // MARK: - State (main queue only)

    private var device: MTDeviceRef?
    private var recognizer = ThreeFingerSwipeRecognizer()

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
        recognizer.reset()
        isActive = false
        print("Grindow: Gesture interceptor stopped")
    }

    // MARK: - Frame handling

    fileprivate func handleTouchFrame(touches: [MTTouch], timestamp: Double, frame: Int32) {
        guard device != nil else { return }
        let contacts = touches.filter { $0.state == 4 }.map {
            TouchPoint(id: $0.identifier, x: $0.normalized.posX, y: $0.normalized.posY)
        }
        switch recognizer.process(contacts) {
        case .began?:
            onGestureBegan?()
        case .swipe(let direction)?:
            onSwipe?(AppSettings.shared.invertSwipes ? direction.reversed : direction)
        case nil:
            break
        }
    }
}
