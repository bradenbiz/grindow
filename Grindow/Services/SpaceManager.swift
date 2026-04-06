import Cocoa
import CoreGraphics

// MARK: - Private CoreGraphics SPI declarations for Space management

/// These are private/undocumented CoreGraphics APIs used by macOS internally
/// for managing Spaces (virtual desktops). They are stable across macOS versions
/// but are not part of the public SDK.

private typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray?

@_silgen_name("CGSGetActiveSpace")
private func CGSGetActiveSpace(_ connection: CGSConnectionID) -> UInt64

@_silgen_name("CGSMoveWorkspaceToSpace")
private func CGSMoveWorkspaceToSpace(_ connection: CGSConnectionID, _ workspaceID: Int, _ spaceID: UInt64)

@_silgen_name("CGSAddWindowsToSpaces")
private func CGSAddWindowsToSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

@_silgen_name("CGSRemoveWindowsFromSpaces")
private func CGSRemoveWindowsFromSpaces(_ connection: CGSConnectionID, _ windowIDs: CFArray, _ spaceIDs: CFArray)

// MARK: - Space information

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let index: Int          // 0-based index in the spaces list
    let type: SpaceType
    let displayUUID: String
    var label: String       // User-visible label (e.g., "Desktop 1", app name for fullscreen)

    enum SpaceType: Int {
        case desktop = 0    // Regular desktop space
        case fullscreen = 4 // Full-screen application space
        case unknown = -1
    }
}

// MARK: - SpaceManager

/// Manages detection and switching of macOS Spaces using private CoreGraphics APIs.
class SpaceManager: ObservableObject {
    static let shared = SpaceManager()

    @Published var spaces: [SpaceInfo] = []
    @Published var activeSpaceID: UInt64 = 0

    private var connection: CGSConnectionID = 0
    private var spaceChangeObserver: NSObjectProtocol?

    private init() {
        connection = CGSMainConnectionID()
        refreshSpaces()
        startObservingSpaceChanges()
    }

    deinit {
        if let observer = spaceChangeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Space Detection

    /// Refreshes the list of all spaces from the system.
    func refreshSpaces() {
        guard let displaySpaces = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return
        }

        var detectedSpaces: [SpaceInfo] = []
        var globalIndex = 0

        for displayInfo in displaySpaces {
            let displayUUID = displayInfo["Display Identifier"] as? String ?? "Unknown"
            guard let spacesArray = displayInfo["Spaces"] as? [[String: Any]] else { continue }

            for spaceDict in spacesArray {
                guard let spaceID = spaceDict["ManagedSpaceID"] as? UInt64 ?? spaceDict["id64"] as? UInt64 else {
                    continue
                }

                let typeRaw = spaceDict["type"] as? Int ?? -1
                let type = SpaceInfo.SpaceType(rawValue: typeRaw) ?? .unknown

                let label: String
                if type == .fullscreen {
                    label = fullscreenAppName(forSpaceID: spaceID) ?? "Full Screen \(globalIndex + 1)"
                } else {
                    label = "Desktop \(globalIndex + 1)"
                }

                let info = SpaceInfo(
                    id: spaceID,
                    index: globalIndex,
                    type: type,
                    displayUUID: displayUUID,
                    label: label
                )
                detectedSpaces.append(info)
                globalIndex += 1
            }
        }

        DispatchQueue.main.async {
            self.spaces = detectedSpaces
            self.activeSpaceID = CGSGetActiveSpace(self.connection)
        }
    }

    /// Returns the active space ID.
    func getActiveSpaceID() -> UInt64 {
        activeSpaceID = CGSGetActiveSpace(connection)
        return activeSpaceID
    }

    // MARK: - Space Switching

    /// Switches to a space by its ID using keyboard shortcut simulation.
    /// This is more reliable than direct CGS API calls for space switching.
    func switchToSpace(id targetSpaceID: UInt64) {
        guard targetSpaceID != activeSpaceID else { return }

        // Find the index of the target space
        guard let targetIndex = spaces.firstIndex(where: { $0.id == targetSpaceID }),
              let currentIndex = spaces.firstIndex(where: { $0.id == activeSpaceID }) else {
            return
        }

        let target = spaces[targetIndex].index
        let current = spaces[currentIndex].index

        // Try direct keyboard shortcut first (Ctrl+Number for spaces 1-9)
        if target < 9 {
            if simulateSpaceSwitchKeyboard(spaceNumber: target + 1) {
                return
            }
        }

        // Fallback: simulate sequential Ctrl+Arrow key presses
        let diff = target - current
        if diff != 0 {
            simulateSequentialArrowSwitch(steps: diff)
        }
    }

    /// Switches to the space at the given grid position using the SpaceGrid.
    func switchToSpace(at position: GridPosition, in grid: SpaceGrid) {
        guard let targetID = grid.spaceID(at: position) else { return }
        switchToSpace(id: targetID)
        grid.currentPosition = position
    }

    // MARK: - Keyboard Simulation

    /// Simulates Ctrl+Number shortcut to jump directly to a space.
    /// Returns true if the shortcut was sent successfully.
    /// Note: User must have "Switch to Desktop N" shortcuts enabled in
    /// System Preferences > Keyboard > Shortcuts > Mission Control.
    private func simulateSpaceSwitchKeyboard(spaceNumber: Int) -> Bool {
        guard spaceNumber >= 1 && spaceNumber <= 9 else { return false }

        // Key codes for 1-9
        let keyCodes: [Int: CGKeyCode] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23,
            6: 22, 7: 26, 8: 28, 9: 25
        ]

        guard let keyCode = keyCodes[spaceNumber] else { return false }

        let source = CGEventSource(stateID: .hidSystemState)

        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            return false
        }

        // Add Control modifier
        keyDown.flags = .maskControl
        keyUp.flags = .maskControl

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)

        return true
    }

    /// Simulates sequential Ctrl+Arrow presses to move between spaces.
    private func simulateSequentialArrowSwitch(steps: Int) {
        let direction: CGKeyCode = steps > 0 ? 124 : 123  // Right : Left arrow
        let count = abs(steps)

        let source = CGEventSource(stateID: .hidSystemState)

        for i in 0..<count {
            let delay = DispatchTimeInterval.milliseconds(i * 300)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: direction, keyDown: true),
                      let keyUp = CGEvent(keyboardEventSource: source, virtualKey: direction, keyDown: false) else {
                    return
                }

                keyDown.flags = .maskControl
                keyUp.flags = .maskControl

                keyDown.post(tap: .cghidEventTap)
                keyUp.post(tap: .cghidEventTap)
            }
        }
    }

    // MARK: - Helpers

    /// Attempts to find the app name for a full-screen space.
    private func fullscreenAppName(forSpaceID spaceID: UInt64) -> String? {
        // Get all windows and find the one on this space
        let options: CGWindowListOption = [.optionAll]
        guard let windowList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowList {
            if let ownerName = window[kCGWindowOwnerName as String] as? String,
               let layer = window[kCGWindowLayer as String] as? Int,
               layer == 0 {
                // Heuristic: check if this window's app might be in the fullscreen space
                // This is imperfect without more private APIs
                return ownerName
            }
        }
        return nil
    }

    // MARK: - Space Change Observation

    private func startObservingSpaceChanges() {
        spaceChangeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSpaceChange()
        }
    }

    private func handleSpaceChange() {
        activeSpaceID = CGSGetActiveSpace(connection)
        // Also refresh spaces in case spaces were added/removed
        refreshSpaces()
    }
}
