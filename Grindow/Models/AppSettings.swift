import Foundation
import SwiftUI

enum TransitionSpeed: String, CaseIterable {
    case instant, quick, smooth
    var rampNanoseconds: UInt64 { self == .smooth ? 60_000_000 : 30_000_000 }
}

/// Persisted user preferences for Grindow.
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var transitionSpeed: TransitionSpeed = .instant {
        didSet { defaults.set(transitionSpeed.rawValue, forKey: "transitionSpeed") }
    }
    @Published var displayLayouts: [String: [UInt64]] = [:] {
        didSet { defaults.set(try? JSONEncoder().encode(displayLayouts), forKey: "displayLayouts") }
    }

    func layout(for display: String, liveIDs: [UInt64]) -> [UInt64] {
        let legacy: [UInt64] = gridLayout.filter { $0 == 0 || liveIDs.contains($0) }
        let saved: [UInt64] = displayLayouts[display] ?? legacy
        return Self.reconcile(saved: saved, liveIDs: liveIDs)
    }

    static func reconcile(saved: [UInt64], liveIDs: [UInt64]) -> [UInt64] {
        var seen = Set<UInt64>()
        var result = saved.map { id -> UInt64 in
            guard id != 0, liveIDs.contains(id), seen.insert(id).inserted else { return 0 }
            return id
        }
        for id in liveIDs where !seen.contains(id) {
            if let empty = result.firstIndex(of: 0) { result[empty] = id }
            else { result.append(id) }
        }
        while result.last == 0 { result.removeLast() }
        return result
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let edgeBehavior = "edgeBehavior"
        static let gridRows = "gridRows"
        static let gridColumns = "gridColumns"
        static let gridLayout = "gridLayout"
        static let isEnabled = "isEnabled"
        static let launchAtLogin = "launchAtLogin"
        static let showBounceAnimation = "showBounceAnimation"
        static let invertSwipes = "invertSwipes"
        static let showSwipeGrid = "showSwipeGrid"
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

    @Published var invertSwipes: Bool {
        didSet { defaults.set(invertSwipes, forKey: Keys.invertSwipes) }
    }

    @Published var showSwipeGrid: Bool {
        didSet { defaults.set(showSwipeGrid, forKey: Keys.showSwipeGrid) }
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
        self.invertSwipes = defaults.object(forKey: Keys.invertSwipes) as? Bool ?? true
        self.showSwipeGrid = defaults.object(forKey: Keys.showSwipeGrid) as? Bool ?? true
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
        transitionSpeed = TransitionSpeed(rawValue: defaults.string(forKey: "transitionSpeed") ?? "") ?? .instant
        if let data = defaults.data(forKey: "displayLayouts"),
           let layouts = try? JSONDecoder().decode([String: [UInt64]].self, from: data) { displayLayouts = layouts }

    }

    func resetToDefaults() {
        displayLayouts = [:]
        transitionSpeed = .instant
        edgeBehavior = .stop
        gridRows = 2
        gridColumns = 3
        isEnabled = true
        launchAtLogin = false
        showBounceAnimation = true
        invertSwipes = true
        showSwipeGrid = true
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
