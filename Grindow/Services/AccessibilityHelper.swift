import Cocoa
import ApplicationServices
import Combine

final class AccessibilityHelper: ObservableObject {
    static let shared = AccessibilityHelper()
    @Published private(set) var isGranted = AXIsProcessTrusted()
    private var timer: Timer?
    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }
    private init() {}

    func startMonitoring() {
        guard timer == nil else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        let granted = AXIsProcessTrusted()
        if granted != isGranted { isGranted = granted }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
