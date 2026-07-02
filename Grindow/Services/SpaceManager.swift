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

@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(_ connection: CGSConnectionID, _ display: CFString, _ space: UInt64)

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

    /// UUID strings of all displays currently connected, matching the format of
    /// CGS's "Display Identifier". Uses public CoreGraphics APIs.
    private func connectedDisplayUUIDs() -> Set<String> {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }

        var uuids = Set<String>()
        for id in ids {
            guard let cf = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { continue }
            uuids.insert(CFUUIDCreateString(nil, cf) as String)
        }
        return uuids
    }

    /// Refreshes the list of all spaces from the system.
    func refreshSpaces() {
        guard let displaySpaces = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return
        }

        var detectedSpaces: [SpaceInfo] = []
        var globalIndex = 0

        // Only include displays that are physically connected right now. macOS
        // retains Space arrangements for displays you've previously attached
        // (external monitors), and CGSCopyManagedDisplaySpaces returns those
        // "ghost" displays too. Their spaces can't be switched to or detected as
        // active, so filtering them out is required for correct navigation.
        let connected = connectedDisplayUUIDs()

        for displayInfo in displaySpaces {
            let displayUUID = displayInfo["Display Identifier"] as? String ?? "Unknown"
            // Keep the display if it's connected. If we couldn't resolve any
            // connected UUIDs (unexpected), fall back to including everything.
            if !connected.isEmpty && !connected.contains(displayUUID) { continue }
            guard let spacesArray = displayInfo["Spaces"] as? [[String: Any]] else { continue }

            for spaceDict in spacesArray {
                guard let spaceID = spaceDict["ManagedSpaceID"] as? UInt64 ?? spaceDict["id64"] as? UInt64 else {
                    continue
                }

                let typeRaw = spaceDict["type"] as? Int ?? -1
                // Skip phantom entries — only real desktop (0) and fullscreen (4) spaces
                // should appear in the grid. Other type values are tiles, dashboards,
                // and other system-internal entries.
                guard typeRaw == 0 || typeRaw == 4 else { continue }
                let type = SpaceInfo.SpaceType(rawValue: typeRaw) ?? .unknown

                let autoLabel: String
                if type == .fullscreen {
                    autoLabel = "Full Screen \(globalIndex + 1)"
                } else {
                    autoLabel = "Desktop \(globalIndex + 1)"
                }
                let label = AppSettings.shared.customName(forSpaceID: spaceID) ?? autoLabel

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

        // Assign synchronously. All callers (init, the space-change observer,
        // and the popover refresh) run on the main thread, and downstream setup
        // (grid arrangement) reads `spaces` synchronously right after calling
        // this — deferring the assignment onto the run loop left the grid empty
        // at launch. Guard the thread just in case a future caller is off-main.
        let apply = {
            self.spaces = detectedSpaces
            self.activeSpaceID = CGSGetActiveSpace(self.connection)
        }
        if Thread.isMainThread {
            apply()
        } else {
            DispatchQueue.main.sync(execute: apply)
        }
    }

    /// Returns the active space ID.
    func getActiveSpaceID() -> UInt64 {
        activeSpaceID = CGSGetActiveSpace(connection)
        return activeSpaceID
    }

    // MARK: - Space Switching

    /// Switches to a space by its ID via the private
    /// `CGSManagedDisplaySetCurrentSpace` SPI. Instant; no keyboard
    /// simulation, no dependency on user-bound shortcuts.
    func switchToSpace(id targetSpaceID: UInt64) {
        guard targetSpaceID != activeSpaceID else { return }
        guard let target = spaces.first(where: { $0.id == targetSpaceID }) else { return }

        let displayUUID = target.displayUUID as CFString
        CGSManagedDisplaySetCurrentSpace(connection, displayUUID, targetSpaceID)

        // The activeSpaceDidChangeNotification observer will reconcile
        // `activeSpaceID` once macOS finishes the transition. Update
        // optimistically so the UI reflects the new state immediately.
        activeSpaceID = targetSpaceID
    }

    /// Switches to the space at the given grid position using the SpaceGrid.
    func switchToSpace(at position: GridPosition, in grid: SpaceGrid) {
        guard let targetID = grid.spaceID(at: position) else { return }
        switchToSpace(id: targetID)
        grid.currentPosition = position
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
