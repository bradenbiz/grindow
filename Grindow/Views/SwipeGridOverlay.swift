import Cocoa
import SwiftUI

/// A passive HUD: never becomes key, activates the app, or intercepts input.
private final class SwipeGridPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class SwipeGridPresentation: ObservableObject {
    @Published var cells: [[UInt64]] = []
    @Published var spaces: [SpaceInfo] = []
    @Published var selectedID: UInt64 = 0
    @Published var isSwitching = false
    @Published var isVisible = false
}

@MainActor
final class SwipeGridOverlayController {
    private let presentation = SwipeGridPresentation()
    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    private var displayID: String?

    func show(grid: SpaceGrid, manager: SpaceManager) {
        guard let screen = screen(for: manager.selectedDisplayID) else { return }
        dismissal?.cancel()
        displayID = manager.selectedDisplayID
        update(grid: grid, manager: manager)

        let panel = panel ?? makePanel()
        // Keep large or unusually shaped grids within the display's visible area.
        let naturalSize = CGSize(width: CGFloat(grid.columns) * 84 + 32,
                                 height: CGFloat(grid.rows) * 60 + 64)
        let scale = min(1, min(480, screen.visibleFrame.width * 0.6) / naturalSize.width,
                        min(380, screen.visibleFrame.height * 0.6) / naturalSize.height)
        let size = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        panel.setFrame(NSRect(x: screen.visibleFrame.midX - size.width / 2,
                              y: screen.visibleFrame.midY - size.height / 2,
                              width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        presentation.isVisible = true

        dismissal = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 900_000_000)
                self?.presentation.isVisible = false
                try await Task.sleep(nanoseconds: 180_000_000)
                self?.hide()
            } catch { /* Another swipe restarted the timer. */ }
        }
    }

    /// Refresh only an existing HUD, so clicks and external Space changes don't summon it.
    func update(grid: SpaceGrid, manager: SpaceManager) {
        guard displayID != nil else { return }
        guard displayID == manager.selectedDisplayID else { hide(); return }
        presentation.cells = grid.grid
        presentation.spaces = manager.spaces
        presentation.selectedID = manager.navigationSpaceID
        presentation.isSwitching = manager.isSwitching
    }

    func hide() {
        dismissal?.cancel()
        dismissal = nil
        presentation.isVisible = false
        panel?.orderOut(nil)
        displayID = nil
    }

    private func makePanel() -> NSPanel {
        let panel = SwipeGridPanel(contentRect: .zero,
                                   styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: SwipeGridOverlayView(presentation: presentation))
        self.panel = panel
        return panel
    }

    private func screen(for display: String) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
                  let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return false }
            return CFUUIDCreateString(nil, uuid) as String == display
        }
    }
}

private struct SwipeGridOverlayView: View {
    @ObservedObject var presentation: SwipeGridPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        GeometryReader { geometry in
            let columns = presentation.cells.first?.count ?? 1
            let naturalSize = CGSize(width: CGFloat(columns) * 84 + 32,
                                     height: CGFloat(presentation.cells.count) * 60 + 64)
            let scale = min(geometry.size.width / naturalSize.width, geometry.size.height / naturalSize.height)
            VStack(spacing: 12) {
                VStack(spacing: 8) {
                    ForEach(presentation.cells.indices, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(presentation.cells[row].indices, id: \.self) { column in
                                cell(presentation.cells[row][column])
                            }
                        }
                    }
                }
                Text(caption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(20)
            .frame(width: naturalSize.width, height: naturalSize.height)
            .background {
                if reduceTransparency {
                    Color(white: 0.16)
                } else {
                    HUDMaterial()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 1))
            .scaleEffect(scale, anchor: .topLeading)
            .opacity(presentation.isVisible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: presentation.isVisible)
        }
        .allowsHitTesting(false)
    }

    private var caption: String {
        let label = presentation.spaces.first { $0.id == presentation.selectedID }?.label ?? "Spaces"
        return presentation.isSwitching ? "Switching to \(label)" : label
    }

    private func cell(_ id: UInt64) -> some View {
        let info = presentation.spaces.first { $0.id == id }
        let selected = id != 0 && id == presentation.selectedID
        return ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(selected ? 0.9 : (info == nil ? 0.025 : 0.12)))
            if let info {
                HStack(spacing: 4) {
                    if info.type == .fullscreen {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    Text("\(info.index + 1)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(selected ? Color.black.opacity(0.8) : Color.white.opacity(0.8))
            }
        }
        .frame(width: 76, height: 52)
    }
}

private struct HUDMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
