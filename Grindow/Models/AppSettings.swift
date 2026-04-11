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

    private init() {
        let edgeRaw = defaults.string(forKey: Keys.edgeBehavior) ?? EdgeBehavior.stop.rawValue
        self.edgeBehavior = EdgeBehavior(rawValue: edgeRaw) ?? .stop
        self.gridRows = defaults.object(forKey: Keys.gridRows) as? Int ?? 2
        self.gridColumns = defaults.object(forKey: Keys.gridColumns) as? Int ?? 3
        self.isEnabled = defaults.object(forKey: Keys.isEnabled) as? Bool ?? true
        self.launchAtLogin = defaults.object(forKey: Keys.launchAtLogin) as? Bool ?? false
        self.showBounceAnimation = defaults.object(forKey: Keys.showBounceAnimation) as? Bool ?? true

        if let data = defaults.data(forKey: Keys.gridLayout),
           let layout = try? JSONDecoder().decode([UInt64].self, from: data) {
            self.gridLayout = layout
        } else {
            self.gridLayout = []
        }
    }

    func resetToDefaults() {
        edgeBehavior = .stop
        gridRows = 2
        gridColumns = 3
        isEnabled = true
        launchAtLogin = false
        showBounceAnimation = true
        gridLayout = []
    }
}
