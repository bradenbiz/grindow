import Foundation

/// Reads macOS's trackpad preferences to see whether the system also acts on
/// three-finger swipes along an axis. Grindow's gesture tap only listens, so
/// when macOS claims an axis, macOS and Grindow would both switch Spaces on
/// the same swipe.
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
