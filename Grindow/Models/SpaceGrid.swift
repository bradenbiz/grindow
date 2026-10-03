import Foundation
import Combine

enum EdgeBehavior: String, Codable, CaseIterable {
    case stop = "stop"
    case wrap = "wrap"
    case bounce = "bounce"

    var displayName: String {
        switch self {
        case .stop: return "Stop at Edge"
        case .wrap: return "Wrap Around"
        case .bounce: return "Bounce"
        }
    }

    var description: String {
        switch self {
        case .stop: return "Nothing happens when swiping past the edge"
        case .wrap: return "Wraps to the opposite side of the grid"
        case .bounce: return "Visual bounce indicating you've reached the edge"
        }
    }
}

enum SwipeDirection {
    case up, down, left, right

    var reversed: SwipeDirection {
        switch self {
        case .up: return .down
        case .down: return .up
        case .left: return .right
        case .right: return .left
        }
    }
}

struct GridPosition: Equatable, Codable, Hashable {
    var row: Int
    var column: Int
}

/// Represents the 2D grid layout of macOS Spaces.
/// Each cell contains a space ID (CGSSpaceID).
class SpaceGrid: ObservableObject {
    @Published var grid: [[UInt64]] = []
    @Published var rows: Int = 1
    @Published var columns: Int = 1
    @Published var currentPosition: GridPosition = GridPosition(row: 0, column: 0)

    /// All space IDs in order, as detected from macOS
    var allSpaceIDs: [UInt64] = []

    /// Arranges detected spaces into a grid with the given dimensions.
    func arrange(spaceIDs: [UInt64], rows: Int, columns: Int) {
        self.allSpaceIDs = spaceIDs
        self.rows = max(1, rows, (spaceIDs.count + max(1, columns) - 1) / max(1, columns))
        self.columns = max(1, columns)

        var grid: [[UInt64]] = []
        var index = 0
        for _ in 0..<self.rows {
            var row: [UInt64] = []
            for _ in 0..<self.columns {
                if index < spaceIDs.count {
                    row.append(spaceIDs[index])
                    index += 1
                } else {
                    row.append(0) // Empty cell
                }
            }
            grid.append(row)
        }
        self.grid = grid
    }

    /// Returns the space ID at the given grid position, or nil if out of bounds or empty.
    func spaceID(at position: GridPosition) -> UInt64? {
        guard position.row >= 0, position.row < rows,
              position.column >= 0, position.column < columns,
              position.row < grid.count, position.column < grid[position.row].count else {
            return nil
        }
        let id = grid[position.row][position.column]
        return id != 0 ? id : nil
    }

    /// Computes the target position after a swipe, given the edge behavior.
    func targetPosition(from current: GridPosition, direction: SwipeDirection, edgeBehavior: EdgeBehavior) -> GridPosition? {
        var target = current

        switch direction {
        case .up: target.row -= 1
        case .down: target.row += 1
        case .left: target.column -= 1
        case .right: target.column += 1
        }

        // Check if target is within bounds
        let inBounds = target.row >= 0 && target.row < rows && target.column >= 0 && target.column < columns

        if inBounds {
            // Check if the target cell has a valid space
            if spaceID(at: target) != nil {
                return target
            }
            return nil
        }

        // Handle out-of-bounds based on edge behavior
        switch edgeBehavior {
        case .stop:
            return nil

        case .bounce:
            // Return nil but caller should trigger bounce animation
            return nil

        case .wrap:
            // Wrap around
            if target.row < 0 {
                target.row = rows - 1
            } else if target.row >= rows {
                target.row = 0
            }
            if target.column < 0 {
                target.column = columns - 1
            } else if target.column >= columns {
                target.column = 0
            }
            if spaceID(at: target) != nil {
                return target
            }
            return nil
        }
    }

    func position(forSpaceID id: UInt64) -> GridPosition? {
        guard id != 0 else { return nil }
        for (row, cells) in grid.enumerated() {
            if let column = cells.firstIndex(of: id) { return GridPosition(row: row, column: column) }
        }
        return nil
    }

    func updateCurrentPosition(forSpaceID id: UInt64) {
        currentPosition = position(forSpaceID: id) ?? GridPosition(row: -1, column: -1)
    }

    /// Moves a space from one grid position to another (for drag-and-drop rearrangement).
    func moveSpace(from source: GridPosition, to destination: GridPosition) {
        guard destination.row >= 0, destination.row < grid.count,
              destination.column >= 0, destination.column < grid[destination.row].count,
              let sourceID = spaceID(at: source) else { return }
        let destID = grid[destination.row][destination.column]

        grid[source.row][source.column] = destID
        grid[destination.row][destination.column] = sourceID
    }
}
