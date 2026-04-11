import Cocoa
import ApplicationServices

/// Handles checking and requesting macOS Accessibility permissions,
/// which are required for CGEventTap to intercept system gestures.
class AccessibilityHelper {
    static let shared = AccessibilityHelper()

    private init() {}

    /// Returns true if the app has Accessibility permissions.
    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permissions.
    /// Opens System Preferences if permissions are not granted.
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Checks permissions and shows an alert if not granted.
    /// Returns true if permissions are already granted.
    @discardableResult
    func checkAndPrompt() -> Bool {
        if isAccessibilityGranted {
            return true
        }

        // Show an informative alert
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Grindow needs Accessibility access to intercept trackpad gestures \
            and enable vertical Space switching.

            Click "Open System Settings" to grant access, then restart Grindow.
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            requestAccessibility()
        }

        return false
    }

    /// Polls for accessibility permission changes.
    /// Calls the completion handler on the main thread when permission is granted.
    func waitForPermission(pollInterval: TimeInterval = 1.0, completion: @escaping () -> Void) {
        Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
}
