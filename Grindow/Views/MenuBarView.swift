import SwiftUI

/// The popover view shown when the user clicks the Grindow menu bar icon.
/// Displays a mini grid showing the current position and quick controls.
struct MenuBarView: View {
    @ObservedObject var spaceGrid: SpaceGrid
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var settings: AppSettings
    @ObservedObject var gestureInterceptor: GestureInterceptor

    var onOpenSettings: () -> Void
    var onOpenGridConfig: () -> Void
    var onQuit: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            headerSection
            miniGrid
            controlsSection
            footerSection
        }
        .padding(16)
        .frame(width: 280)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("Grindow")
                .font(.headline)

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(gestureInterceptor.isActive ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(gestureInterceptor.isActive ? "Active" : "Inactive")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Mini Grid

    private var miniGrid: some View {
        VStack(spacing: 2) {
            ForEach(0..<spaceGrid.rows, id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(0..<spaceGrid.columns, id: \.self) { col in
                        miniGridCell(row: row, col: col)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func miniGridCell(row: Int, col: Int) -> some View {
        let position = GridPosition(row: row, column: col)
        let hasSpace = spaceGrid.spaceID(at: position) != nil
        let isCurrent = spaceGrid.currentPosition == position && hasSpace
        let spaceInfo = spaceGrid.spaceID(at: position).flatMap { id in
            spaceManager.spaces.first(where: { $0.id == id })
        }

        return Button(action: {
            if let targetID = spaceGrid.spaceID(at: position) {
                spaceManager.switchToSpace(id: targetID)
                spaceGrid.currentPosition = position
            }
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(isCurrent ? Color.accentColor : (hasSpace ? Color(nsColor: .controlColor) : Color.clear))

                if let info = spaceInfo {
                    Text(shortLabel(for: info))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isCurrent ? .white : .primary)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: 36, height: 28)
        .help(spaceInfo?.label ?? "Empty")
    }

    /// Compact label for a tiny grid cell: the start of a custom name, or a
    /// number (prefixed for full-screen spaces) so cells are distinguishable
    /// instead of every desktop showing "Des".
    private func shortLabel(for info: SpaceInfo) -> String {
        if let custom = settings.customName(forSpaceID: info.id) {
            return String(custom.prefix(4))
        }
        return info.type == .fullscreen ? "⤢\(info.index + 1)" : "\(info.index + 1)"
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(spacing: 6) {
            Toggle("Enable Vertical Swipes", isOn: $settings.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Picker("Edge Behavior", selection: $settings.edgeBehavior) {
                ForEach(EdgeBehavior.allCases, id: \.self) { behavior in
                    Text(behavior.displayName).tag(behavior)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 4) {
            Divider()

            HStack(spacing: 12) {
                Button("Grid Layout") {
                    onOpenGridConfig()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Button("Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderless)
                .font(.caption)

                Spacer()

                Button("Quit") {
                    onQuit()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundColor(.red)
            }
        }
    }
}
