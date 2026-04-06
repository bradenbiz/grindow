import Cocoa
import SwiftUI

/// The main application delegate that coordinates all Grindow components.
///
/// Responsibilities:
/// - Sets up the menu bar status item
/// - Initializes and connects the gesture interceptor, space manager, and grid
/// - Handles swipe events and translates them into space switches
/// - Manages the settings and grid configuration windows
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components

    private let spaceManager = SpaceManager.shared
    private let gestureInterceptor = GestureInterceptor.shared
    private let settings = AppSettings.shared
    private let spaceGrid = SpaceGrid()

    // MARK: - UI

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var settingsWindow: NSWindow?
    private var gridConfigWindow: NSWindow?
    private var eventMonitor: Any?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupPopover()
        setupSpaceGrid()
        setupGestureInterceptor()
        checkAccessibility()
        setupEventMonitor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        gestureInterceptor.stop()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            // Use a grid icon for the menu bar
            let image = NSImage(systemSymbolName: "square.grid.3x3", accessibilityDescription: "Grindow")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover)
            button.target = self
        }
    }

    // MARK: - Popover

    private func setupPopover() {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 280, height: 360)
        popover.behavior = .transient
        popover.animates = true

        let menuBarView = MenuBarView(
            spaceGrid: spaceGrid,
            spaceManager: spaceManager,
            settings: settings,
            gestureInterceptor: gestureInterceptor,
            onOpenSettings: { [weak self] in
                self?.popover.close()
                self?.openSettingsWindow()
            },
            onOpenGridConfig: { [weak self] in
                self?.popover.close()
                self?.openGridConfigWindow()
            },
            onQuit: {
                NSApplication.shared.terminate(nil)
            }
        )

        popover.contentViewController = NSHostingController(rootView: menuBarView)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }

        if popover.isShown {
            popover.close()
        } else {
            // Refresh data before showing
            spaceManager.refreshSpaces()
            let activeID = spaceManager.getActiveSpaceID()
            spaceGrid.updateCurrentPosition(forSpaceID: activeID)

            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - Click-outside-to-close monitor

    private func setupEventMonitor() {
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            if let popover = self?.popover, popover.isShown {
                popover.close()
            }
        }
    }

    // MARK: - Space Grid

    private func setupSpaceGrid() {
        let spaceIDs = spaceManager.spaces.map { $0.id }

        // Restore saved layout or auto-arrange
        if !settings.gridLayout.isEmpty {
            spaceGrid.arrange(
                spaceIDs: settings.gridLayout,
                rows: settings.gridRows,
                columns: settings.gridColumns
            )
        } else {
            spaceGrid.arrange(
                spaceIDs: spaceIDs,
                rows: settings.gridRows,
                columns: settings.gridColumns
            )
        }

        // Set initial position
        let activeID = spaceManager.getActiveSpaceID()
        spaceGrid.updateCurrentPosition(forSpaceID: activeID)

        // Observe space changes to update current position
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let newActiveID = self.spaceManager.getActiveSpaceID()
            self.spaceGrid.updateCurrentPosition(forSpaceID: newActiveID)
        }
    }

    // MARK: - Gesture Interceptor

    private func setupGestureInterceptor() {
        gestureInterceptor.onSwipe = { [weak self] direction in
            self?.handleSwipe(direction: direction)
        }

        if settings.isEnabled && AccessibilityHelper.shared.isAccessibilityGranted {
            gestureInterceptor.start()
        }

        // Observe settings changes
        settings.$isEnabled.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            guard let self = self else { return }
            if enabled && AccessibilityHelper.shared.isAccessibilityGranted {
                self.gestureInterceptor.start()
            } else {
                self.gestureInterceptor.stop()
            }
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Swipe Handling

    private func handleSwipe(direction: SwipeDirection) {
        guard settings.isEnabled else { return }

        // Refresh current position from active space
        let activeID = spaceManager.getActiveSpaceID()
        spaceGrid.updateCurrentPosition(forSpaceID: activeID)

        let current = spaceGrid.currentPosition

        if let targetPosition = spaceGrid.targetPosition(
            from: current,
            direction: direction,
            edgeBehavior: settings.edgeBehavior
        ) {
            // Valid target — switch to it
            spaceManager.switchToSpace(at: targetPosition, in: spaceGrid)
        } else {
            // At the edge
            if settings.edgeBehavior == .bounce && settings.showBounceAnimation {
                BounceOverlayController.shared.showBounce(direction: direction)
            }
        }
    }

    // MARK: - Accessibility

    private func checkAccessibility() {
        if !AccessibilityHelper.shared.isAccessibilityGranted {
            AccessibilityHelper.shared.checkAndPrompt()

            // Poll for permission grant
            AccessibilityHelper.shared.waitForPermission { [weak self] in
                guard let self = self else { return }
                if self.settings.isEnabled {
                    self.gestureInterceptor.start()
                }
            }
        }
    }

    // MARK: - Windows

    private func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView(settings: settings)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Grindow Settings"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 460, height: 420))
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        settingsWindow = window
    }

    private func openGridConfigWindow() {
        if let window = gridConfigWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Refresh spaces before showing
        spaceManager.refreshSpaces()

        let gridView = GridConfigView(
            spaceManager: spaceManager,
            spaceGrid: spaceGrid,
            settings: settings
        )
        let hostingController = NSHostingController(rootView: gridView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Grid Layout"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 480))
        window.center()
        window.delegate = self
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        gridConfigWindow = window
    }
}

// MARK: - NSWindowDelegate

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === settingsWindow {
            settingsWindow = nil
        } else if window === gridConfigWindow {
            gridConfigWindow = nil
        }
    }
}

// MARK: - Combine import for sink

import Combine
