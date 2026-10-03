import Cocoa
import CoreGraphics

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: UInt32, _ display: CFString?) -> CFArray?

@MainActor
class SpaceManager: ObservableObject {
    static let shared = SpaceManager()
    @Published private(set) var displays: [DisplaySpaces] = []
    @Published private(set) var spaces: [SpaceInfo] = []
    @Published private(set) var activeSpaceID: UInt64 = 0
    @Published private(set) var selectedDisplayID = ""
    @Published private(set) var isSwitching = false
    @Published var lastError: String?
    var onChange: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    private lazy var coordinator: SpaceSwitchCoordinator = {
        let worker = SpaceSwitchCoordinator(snapshot: { [weak self] id in
            self?.readDisplays().first { $0.id == id }
        }, post: { [weak self] right, display, steps in
            guard let self else { throw SpaceSwitchCoordinator.Failure.unavailable }
            try await self.postSwipe(right: right, display: display, steps: steps)
        })
        worker.onProgress = { [weak self] in self?.refreshSpaces(); self?.onChange?() }
        worker.onFinish = { [weak self] error in
            guard let self else { return }
            self.isSwitching = false
            self.lastError = error?.localizedDescription
            self.refreshSpaces()
            self.onChange?()
        }
        return worker
    }()

    private init() {
        refreshSpaces()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshSpaces(); self?.onChange?() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancelSwitching(); self?.refreshSpaces(); self?.onChange?() }
        })
    }

    private func uuid(for id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    private func screenID(_ screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    func screen(forDisplayUUID display: String) -> NSScreen? {
        NSScreen.screens.first { screenID($0).flatMap { uuid(for: $0) } == display }
    }

    private func readDisplays() -> [DisplaySpaces] {
        guard strafe_cgs_available(),
              let roster = CGSCopyManagedDisplaySpaces(CGSMainConnectionID(), nil) as? [[String: Any]] else { return [] }
        var connected: [String: String] = [:]
        for (index, screen) in NSScreen.screens.enumerated() {
            if let number = screenID(screen), let id = uuid(for: number) {
                connected[id] = "\(index + 1): \(screen.localizedName)"
            }
        }
        return DisplaySpaces.parse(roster, connected: connected, mainDisplayID: uuid(for: CGMainDisplayID()) ?? "")
    }

    func refreshSpaces() {
        displays = readDisplays()
        if !displays.contains(where: { $0.id == selectedDisplayID }) {
            selectedDisplayID = displays.first?.id ?? ""
        }
        let selected = displays.first { $0.id == selectedDisplayID }
        spaces = (selected?.spaces ?? []).map { info in
            var copy = info
            copy.label = AppSettings.shared.customName(forSpaceID: info.id) ?? info.label
            return copy
        }
        activeSpaceID = selected?.currentSpaceID ?? 0
    }

    func selectDisplay(_ id: String) {
        guard displays.contains(where: { $0.id == id }), id != selectedDisplayID else { return }
        selectedDisplayID = id
        refreshSpaces()
        onChange?()
    }

    /// Called once when raw touch tracking begins, so the gesture keeps its display.
    func selectCursorDisplay() {
        guard let point = CGEvent(source: nil)?.location else { return }
        for screen in NSScreen.screens {
            if let number = screenID(screen), CGDisplayBounds(number).contains(point), let id = uuid(for: number) {
                selectDisplay(id)
                return
            }
        }
    }

    func getActiveSpaceID() -> UInt64 {
        refreshSpaces()
        return activeSpaceID
    }

    var navigationSpaceID: UInt64 {
        coordinator.displayID == selectedDisplayID ? (coordinator.targetID ?? activeSpaceID) : activeSpaceID
    }

    @discardableResult
    func switchToSpace(id target: UInt64) -> Bool {
        guard AccessibilityHelper.shared.isAccessibilityGranted else {
            lastError = "Grant Accessibility access in Settings to switch Spaces."
            return false
        }
        guard !strafe_is_expose_active() else {
            lastError = "Close Mission Control or App Exposé before navigating the grid."
            return false
        }
        guard coordinator.request(target: target, display: selectedDisplayID) else {
            lastError = "Finish switching on the other display, or refresh the selected Space."
            return false
        }
        lastError = nil
        isSwitching = true
        return true
    }

    func cancelSwitching() { coordinator.cancel() }

    private func postSwipe(right: Bool, display: String, steps: Int) async throws {
        guard AccessibilityHelper.shared.isAccessibilityGranted, !strafe_is_expose_active(),
              let screen = self.screen(forDisplayUUID: display), let number = screenID(screen) else { throw SpaceSwitchCoordinator.Failure.unavailable }
        let bounds = CGDisplayBounds(number)
        let point = CGPoint(x: bounds.midX, y: bounds.midY)
        let speed = AppSettings.shared.transitionSpeed
        if steps > 1 || speed == .instant {
            // A synchronous C loop posts the whole route before yielding. Verify
            // only after posting; do not deliberately present each intermediate Space.
            guard steps > 0, steps <= 128,
                  strafe_post_switch_gestures(right ? StrafeDirectionRight : StrafeDirectionLeft, UInt32(steps), point) else {
                throw SpaceSwitchCoordinator.Failure.postFailed
            }
            return
        }
        let sign: Double = right ? 1 : -1
        guard strafe_post_dock_swipe_phase(1, 0, 0, point) else { throw SpaceSwitchCoordinator.Failure.postFailed }
        do {
            for step in 1...6 {
                try Task.checkCancellation()
                let fraction = Double(step) / 6
                guard strafe_post_dock_swipe_phase(2, sign * 0.35 * fraction, sign * 130 * fraction, point) else {
                    throw SpaceSwitchCoordinator.Failure.postFailed
                }
                try await Task.sleep(nanoseconds: speed.rampNanoseconds / 6)
            }
            guard strafe_post_dock_swipe_phase(4, sign * 0.35, sign * 130, point) else {
                throw SpaceSwitchCoordinator.Failure.postFailed
            }
        } catch {
            // Always close a started gesture, including cancellation on disable/unplug.
            _ = strafe_post_dock_swipe_phase(8, 0, 0, point)
            throw error
        }
    }
}
