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
                // Skip phantom entries — only real desktop (0) and fullscreen (4) spaces
                // should appear in the grid. Other type values are tiles, dashboards,
                // and other system-internal entries.
                guard typeRaw == 0 || typeRaw == 4 else { continue }
                let type = SpaceInfo.SpaceType(rawValue: typeRaw) ?? .unknown

                let label: String
                if type == .fullscreen {
                    label = "Full Screen \(globalIndex + 1)"
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
