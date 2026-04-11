import SwiftUI

/// A transparent overlay window that shows a subtle bounce animation
/// when the user swipes past the edge of the grid with bounce behavior enabled.
struct BounceOverlayView: View {
    let direction: SwipeDirection
    @State private var opacity: Double = 0.6
    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Gradient edge indicator
                gradientOverlay(size: geometry.size)
                    .opacity(opacity)
                    .offset(x: horizontalOffset, y: verticalOffset + offset)

                // Arrow indicator
                arrowIndicator
                    .opacity(opacity)
                    .offset(x: arrowHorizontalOffset(size: geometry.size),
                            y: arrowVerticalOffset(size: geometry.size) + offset)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.15)) {
                offset = bounceOffset
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.15)) {
                offset = 0
                opacity = 0
            }
        }
    }

    private func gradientOverlay(size: CGSize) -> some View {
        Group {
            switch direction {
            case .up:
                LinearGradient(colors: [.white.opacity(0.3), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .position(x: size.width / 2, y: 30)

            case .down:
                LinearGradient(colors: [.clear, .white.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .position(x: size.width / 2, y: size.height - 30)

            case .left:
                LinearGradient(colors: [.white.opacity(0.3), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                    .frame(maxHeight: .infinity)
                    .position(x: 30, y: size.height / 2)

            case .right:
                LinearGradient(colors: [.clear, .white.opacity(0.3)],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 60)
                    .frame(maxHeight: .infinity)
                    .position(x: size.width - 30, y: size.height / 2)
            }
        }
    }

    private var arrowIndicator: some View {
        Image(systemName: arrowSystemName)
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.white.opacity(0.7))
    }

    private var arrowSystemName: String {
        switch direction {
        case .up: return "chevron.up"
        case .down: return "chevron.down"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        }
    }

    private var bounceOffset: CGFloat {
        switch direction {
        case .up: return -15
        case .down: return 15
        case .left, .right: return 0
        }
    }

    private var horizontalOffset: CGFloat { 0 }
    private var verticalOffset: CGFloat { 0 }

    private func arrowHorizontalOffset(size: CGSize) -> CGFloat {
        switch direction {
        case .left: return 30
        case .right: return size.width - 30
        default: return size.width / 2
        }
    }

    private func arrowVerticalOffset(size: CGSize) -> CGFloat {
        switch direction {
        case .up: return 30
        case .down: return size.height - 30
        default: return size.height / 2
        }
    }
}

// MARK: - Bounce Overlay Window Controller

/// Manages a borderless transparent window for showing the bounce effect.
class BounceOverlayController {
    static let shared = BounceOverlayController()

    private var overlayWindow: NSWindow?

    func showBounce(direction: SwipeDirection) {
        guard let screen = NSScreen.main else { return }

        // Remove existing overlay
        overlayWindow?.close()

        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]

        let hostingView = NSHostingView(rootView: BounceOverlayView(direction: direction))
        window.contentView = hostingView

        window.orderFront(nil)
        overlayWindow = window

        // Auto-dismiss after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.overlayWindow?.close()
            self?.overlayWindow = nil
        }
    }
}
