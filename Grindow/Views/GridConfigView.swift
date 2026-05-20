import SwiftUI

/// The main grid configuration view where users arrange their Spaces in a 2D grid.
/// Shows detected spaces and lets users drag them into position.
struct GridConfigView: View {
    @ObservedObject var spaceManager: SpaceManager
    @ObservedObject var spaceGrid: SpaceGrid
    @ObservedObject var settings: AppSettings

    @State private var draggedSpace: UInt64?
    @State private var hoveredCell: GridPosition?
    @State private var renamingSpaceID: UInt64?
    @State private var renameText: String = ""

    var body: some View {
        VStack(spacing: 16) {
            headerSection
            gridDimensionControls
            gridView
            legendSection
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 400)
        .alert(
            "Rename Space",
            isPresented: Binding(
                get: { renamingSpaceID != nil },
                set: { if !$0 { renamingSpaceID = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) {
                renamingSpaceID = nil
                renameText = ""
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 4) {
            Text("Space Grid Layout")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Arrange your Spaces in a 2D grid. Swipe vertically to move between rows.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Dimension Controls

    private var gridDimensionControls: some View {
        HStack(spacing: 20) {
            HStack {
                Text("Rows:")
                    .font(.body)
                Stepper("\(settings.gridRows)", value: $settings.gridRows, in: 1...6)
                    .frame(width: 100)
            }

            HStack {
                Text("Columns:")
                    .font(.body)
                Stepper("\(settings.gridColumns)", value: $settings.gridColumns, in: 1...9)
                    .frame(width: 100)
            }

            Spacer()

            Button("Auto-Arrange") {
                autoArrangeSpaces()
            }
            .buttonStyle(.bordered)

            Button("Refresh Spaces") {
                spaceManager.refreshSpaces()
                autoArrangeSpaces()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
    }

    // MARK: - Grid

    private var gridView: some View {
        VStack(spacing: 4) {
            ForEach(0..<settings.gridRows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(0..<settings.gridColumns, id: \.self) { col in
                        gridCell(row: row, col: col)
                    }
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func gridCell(row: Int, col: Int) -> some View {
        let position = GridPosition(row: row, column: col)
        let spaceID = spaceGrid.spaceID(at: position)
        let isCurrentSpace = spaceGrid.currentPosition == position && spaceID != nil
        let spaceInfo = spaceID.flatMap { id in spaceManager.spaces.first(where: { $0.id == id }) }
        let isHovered = hoveredCell == position

        return ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(cellBackgroundColor(isCurrentSpace: isCurrentSpace, hasSpace: spaceID != nil, isHovered: isHovered))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isCurrentSpace ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: isCurrentSpace ? 2 : 1
                        )
                )

            VStack(spacing: 4) {
                if let info = spaceInfo {
                    Image(systemName: info.type == .fullscreen ? "rectangle.fill" : "desktopcomputer")
                        .font(.title3)
                        .foregroundColor(isCurrentSpace ? .white : .primary)

                    Text(info.label)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(isCurrentSpace ? .white : .primary)
                } else {
                    Image(systemName: "plus.dashed")
                        .font(.title3)
                        .foregroundColor(.secondary)

                    Text("Empty")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 80, minHeight: 70)
        .onDrop(of: [.plainText], isTargeted: Binding(
            get: { hoveredCell == position },
            set: { if $0 { hoveredCell = position } else if hoveredCell == position { hoveredCell = nil } }
        )) { providers in
            handleDrop(providers: providers, at: position)
        }
        .onDrag {
            if let id = spaceID {
                draggedSpace = id
                return NSItemProvider(object: "\(id)" as NSString)
            }
            return NSItemProvider()
        }
        .contextMenu {
            if let id = spaceID {
                Button("Rename…") { beginRename(spaceID: id) }
                if settings.customName(forSpaceID: id) != nil {
                    Button("Reset to Default Name") {
                        settings.setCustomName(nil, forSpaceID: id)
                        spaceManager.refreshSpaces()
                    }
                }
            }
        }
        .help(spaceInfo?.label ?? "Empty cell (\(row), \(col))")
    }

    private func beginRename(spaceID: UInt64) {
        renameText = settings.customName(forSpaceID: spaceID)
            ?? spaceManager.spaces.first(where: { $0.id == spaceID })?.label
            ?? ""
        renamingSpaceID = spaceID
    }

    private func commitRename() {
        guard let id = renamingSpaceID else { return }
        settings.setCustomName(renameText, forSpaceID: id)
        renamingSpaceID = nil
        renameText = ""
        spaceManager.refreshSpaces()
    }

    private func cellBackgroundColor(isCurrentSpace: Bool, hasSpace: Bool, isHovered: Bool) -> Color {
        if isCurrentSpace {
            return Color.accentColor
        }
        if isHovered {
            return Color.accentColor.opacity(0.2)
        }
        if hasSpace {
            return Color(nsColor: .controlColor)
        }
        return Color(nsColor: .controlBackgroundColor)
    }

    // MARK: - Legend

    private var legendSection: some View {
        HStack(spacing: 16) {
            legendItem(color: .accentColor, label: "Current Space")
            legendItem(color: Color(nsColor: .controlColor), label: "Assigned Space")
            legendItem(color: Color(nsColor: .controlBackgroundColor), label: "Empty Slot")

            Spacer()

            Text("\(spaceManager.spaces.count) spaces detected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.gray.opacity(0.3)))
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Actions

    private func autoArrangeSpaces() {
        let spaceIDs = spaceManager.spaces.map { $0.id }
        spaceGrid.arrange(spaceIDs: spaceIDs, rows: settings.gridRows, columns: settings.gridColumns)

        // Update current position
        let activeID = spaceManager.getActiveSpaceID()
        spaceGrid.updateCurrentPosition(forSpaceID: activeID)

        // Save layout
        settings.gridLayout = spaceIDs
    }

    private func handleDrop(providers: [NSItemProvider], at position: GridPosition) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.plain-text", options: nil) { item, _ in
            guard let data = item as? Data,
                  let text = String(data: data, encoding: .utf8),
                  let sourceID = UInt64(text) else { return }

            DispatchQueue.main.async {
                // Find source position
                for r in 0..<spaceGrid.rows {
                    for c in 0..<spaceGrid.columns {
                        let pos = GridPosition(row: r, column: c)
                        if spaceGrid.spaceID(at: pos) == sourceID {
                            spaceGrid.moveSpace(from: pos, to: position)
                            return
                        }
                    }
                }
            }
        }
        return true
    }
}
