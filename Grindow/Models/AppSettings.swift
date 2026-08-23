import Foundation
import SwiftUI

/// Persisted user preferences for Grindow.
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let edgeBehavior = "edgeBehavior"
        static let gridRows = "gridRows"
        static let gridColumns = "gridColumns"
        static let gridLayout = "gridLayout"
        static let isEnabled = "isEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let showBounceAnimation = "showBounceAnimation"
        static let invertVerticalSwipe = "invertVerticalSwipe"
        static let spaceNames = "spaceNames"
        static let hasShownFirstRunGuide = "hasShownFirstRunGuide"
    }

    @Published var edgeBehavior: EdgeBehavior {
        didSet { defaults.set(edgeBehavior.rawValue, forKey: Keys.edgeBehavior) }
    }

    @Published var gridRows: Int {
        didSet { defaults.set(gridRows, forKey: Keys.gridRows) }
    }

    @Published var gridColumns: Int {
        didSet { defaults.set(gridColumns, forKey: Keys.gridColumns) }
    }

    /// Serialized grid layout: flat array of space IDs in row-major order.
    @Published var gridLayout: [UInt64] {
        didSet {
            let data = try? JSONEncoder().encode(gridLayout)
            defaults.set(data, forKey: Keys.gridLayout)
        }
    }

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: Keys.isEnabled) }
    }

    @Published var launchAtLogin: Bool {
        didSet { defaults.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    @Published var showBounceAnimation: Bool {
        didSet { defaults.set(showBounceAnimation, forKey: Keys.showBounceAnimation) }
    }

    @Published var invertVerticalSwipe: Bool {
        didSet { defaults.set(invertVerticalSwipe, forKey: Keys.invertVerticalSwipe) }
    }

    @Published var hasShownFirstRunGuide: Bool {
        didSet { defaults.set(hasShownFirstRunGuide, forKey: Keys.hasShownFirstRunGuide) }
    }

    /// Custom user-assigned names per space. Keys are space IDs as strings
    /// (JSON-friendly); empty / missing entries fall back to the auto label.
    @Published var spaceNames: [String: String] {
        didSet {
            let data = try? JSONEncoder().encode(spaceNames)
            defaults.set(data, forKey: Keys.spaceNames)
        }
    }

    private init() {
        let edgeRaw = defaults.string(forKey: Keys.edgeBehavior) ?? EdgeBehavior.stop.rawValue
        self.edgeBehavior = EdgeBehavior(rawValue: edgeRaw) ?? .stop
        self.gridRows = defaults.object(forKey: Keys.gridRows) as? Int ?? 2
        self.gridColumns = defaults.object(forKey: Keys.gridColumns) as? Int ?? 3
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.showBounceAnimation = defaults.object(forKey: Keys.showBounceAnimation) as? Bool ?? true
        self.invertVerticalSwipe = defaults.object(forKey: Keys.invertVerticalSwipe) as? Bool ?? false
        self.hasShownFirstRunGuide = defaults.object(forKey: Keys.hasShownFirstRunGuide) as? Bool ?? false

        if let data = defaults.data(forKey: Keys.gridLayout),
           let layout = try? JSONDecoder().decode([UInt64].self, from: data) {
            self.gridLayout = layout
        } else {
            self.gridLayout = []
        }

        if let data = defaults.data(forKey: Keys.spaceNames),
           let names = try? JSONDecoder().decode([String: String].self, from: data) {
            self.spaceNames = names
        } else {
            self.spaceNames = [:]
        }
    }

    func resetToDefaults() {
        edgeBehavior = .stop
        gridRows = 2
        gridColumns = 3
        isEnabled = true
        launchAtLogin = false
        showBounceAnimation = true
        invertVerticalSwipe = false
        hasShownFirstRunGuide = false
        gridLayout = []
        spaceNames = [:]
    }

    // MARK: - Per-space names

    func customName(forSpaceID id: UInt64) -> String? {
        let raw = spaceNames[String(id)]?.trimmingCharacters(in: .whitespaces)
        return (raw?.isEmpty == false) ? raw : nil
    }

    func setCustomName(_ name: String?, forSpaceID id: UInt64) {
        let trimmed = name?.trimmingCharacters(in: .whitespaces) ?? ""
        if trimmed.isEmpty {
            spaceNames.removeValue(forKey: String(id))
        } else {
            spaceNames[String(id)] = trimmed
        }
    }
}
