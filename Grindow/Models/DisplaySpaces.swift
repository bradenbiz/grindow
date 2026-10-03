import Foundation

struct SpaceInfo: Identifiable, Equatable {
    let id: UInt64
    let index: Int
    let type: SpaceType
    let displayUUID: String
    var label: String
    /// 1-based position among Spaces of the same type, so desktops are numbered
    /// the way Mission Control numbers them even when full-screen Spaces sit between.
    var number: Int = 0

    enum SpaceType: Int {
        case desktop = 0, fullscreen = 4, unknown = -1
    }
}

struct DisplaySpaces: Identifiable, Equatable {
    let id: String
    let name: String
    let spaces: [SpaceInfo]
    let currentSpaceID: UInt64

    /// No global active-space fallback: another monitor's active Space is not ours.
    static func parse(_ roster: [[String: Any]], connected: [String: String], mainDisplayID: String) -> [DisplaySpaces] {
        roster.compactMap { display in
            guard let rawID = display["Display Identifier"] as? String else { return nil }
            let id = rawID == "Main" ? mainDisplayID : rawID
            guard let name = connected[id], let entries = display["Spaces"] as? [[String: Any]] else { return nil }
            var counts: [SpaceInfo.SpaceType: Int] = [:]
            let spaces = entries.compactMap { entry -> SpaceInfo? in
                guard let sid = (entry["ManagedSpaceID"] as? NSNumber ?? entry["id64"] as? NSNumber)?.uint64Value,
                      let rawType = entry["type"] as? Int, rawType == 0 || rawType == 4 else { return nil }
                return SpaceInfo(id: sid, index: 0, type: SpaceInfo.SpaceType(rawValue: rawType)!, displayUUID: id, label: "")
            }.enumerated().map { index, space -> SpaceInfo in
                let number = (counts[space.type] ?? 0) + 1
                counts[space.type] = number
                return SpaceInfo(id: space.id, index: index, type: space.type, displayUUID: id,
                                 label: space.type == .fullscreen ? "Full Screen \(number)" : "Desktop \(number)",
                                 number: number)
            }
            let current = display["Current Space"] as? [String: Any]
            let currentID = (current?["ManagedSpaceID"] as? NSNumber ?? current?["id64"] as? NSNumber)?.uint64Value ?? 0
            return DisplaySpaces(id: id, name: name, spaces: spaces, currentSpaceID: currentID)
        }
    }
}
