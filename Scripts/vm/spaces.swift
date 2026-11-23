// Prints each display's Spaces and marks the active one, for checking Space
// switches from a script: `swift spaces.swift` (or `grindow-vm spaces`).
// Uses the same private CGS call as Grindow's SpaceManager. Run it in the GUI
// user's session (SSH as that user works).
import CoreGraphics
import Foundation

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> UInt32
@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: UInt32, _ display: CFString?) -> CFArray?

guard let displays = CGSCopyManagedDisplaySpaces(CGSMainConnectionID(), nil) as? [[String: Any]] else {
    FileHandle.standardError.write("CGSCopyManagedDisplaySpaces returned nothing\n".data(using: .utf8)!)
    exit(1)
}
for display in displays {
    let id = display["Display Identifier"] as? String ?? "?"
    let current = (display["Current Space"] as? [String: Any])?["ManagedSpaceID"] as? Int
    let spaces = display["Spaces"] as? [[String: Any]] ?? []
    let cells = spaces.enumerated().map { index, space -> String in
        let sid = space["ManagedSpaceID"] as? Int
        let fullScreen = (space["type"] as? Int) == 4
        let label = fullScreen ? "F\(index + 1)" : "\(index + 1)"
        return sid == current ? "[\(label)]" : " \(label) "
    }
    print("\(id): \(cells.joined(separator: " "))")
}
