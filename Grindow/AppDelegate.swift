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
        setupEventMonitor()
        showFirstRunGuideIfNeeded()
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
            // Always show the latest state when opening.
            syncGridToSystem()
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
        rebuildGrid()
        spaceGrid.updateCurrentPosition(forSpaceID: spaceManager.getActiveSpaceID())

        // Keep the grid in sync as spaces are switched, added, or removed.
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncGridToSystem()
        }
    }

    /// Pulls the latest spaces from the system and reconciles the grid: rebuilds
    /// membership if the set changed, then updates the current position. Cheap
    /// enough to call on every space change and whenever the popover opens, so
    /// the grid is always current without any manual "refresh".
    private func syncGridToSystem() {
        spaceManager.refreshSpaces()
        let live = Set(spaceManager.spaces.map { $0.id })
        let known = Set(spaceGrid.allSpaceIDs.filter { $0 != 0 })
        if live != known {
            rebuildGrid()
        }
        spaceGrid.updateCurrentPosition(forSpaceID: spaceManager.getActiveSpaceID())
    }

    /// (Re)arranges the grid from the current spaces, preferring a saved layout
    /// only when all of its IDs still correspond to real spaces.
    private func rebuildGrid() {
        let spaceIDs = spaceManager.spaces.map { $0.id }
        guard !spaceIDs.isEmpty else { return }  // never persist an empty grid
        let currentSet = Set(spaceIDs)

        // Discard a saved layout if any of its IDs no longer correspond to a
        // real space — happens after our phantom-space filter kicks in, or
        // when the user adds/removes desktops outside Grindow.
        let savedNonZero = settings.gridLayout.filter { $0 != 0 }
        let savedAllValid = !savedNonZero.isEmpty
            && Set(savedNonZero) == currentSet

        if savedAllValid {
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
            settings.gridLayout = spaceIDs
        }
    }

    // MARK: - Gesture Interceptor

    private func setupGestureInterceptor() {
        gestureInterceptor.onSwipe = { [weak self] direction in
            self?.handleSwipe(direction: direction)
        }

        // MultitouchSupport doesn't require Accessibility — only the
        // keyboard-simulation path for space switching does. Start the
        // interceptor unconditionally if the user has Grindow enabled.
        if settings.isEnabled {
            gestureInterceptor.start()
        }

        settings.$isEnabled.receive(on: DispatchQueue.main).sink { [weak self] enabled in
            guard let self = self else { return }
            if enabled {
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

        let target = spaceGrid.targetPosition(
            from: current,
            direction: direction,
            edgeBehavior: settings.edgeBehavior
        )

        if let targetPosition = target {
            // Valid target — switch to it
            spaceManager.switchToSpace(at: targetPosition, in: spaceGrid)
        } else {
            // At the edge
            if settings.edgeBehavior == .bounce && settings.showBounceAnimation {
                BounceOverlayController.shared.showBounce(direction: direction)
            }
        }
    }

    // MARK: - First-Run Guide

    /// On first launch, prompt the user to disable macOS's built-in three-finger
    /// gestures so Grindow's vertical-swipe handler isn't fighting Mission Control.
    private func showFirstRunGuideIfNeeded() {
        guard !settings.hasShownFirstRunGuide else { return }

        // Defer so the menu bar item shows up first and the alert isn't presented
        // before the rest of the UI is ready.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }

            let alert = NSAlert()
            alert.messageText = "One quick setup step"
            alert.informativeText = """
            Grindow uses three-finger vertical swipes to navigate your space grid. \
            macOS uses the same gesture for Mission Control and App Exposé by default, \
            so they will fight each other until you turn the built-in versions off.

            In System Settings → Trackpad → More Gestures, set both \
            "Swipe between full-screen apps" and "Mission Control" to "Off" \
            (or switch them to four fingers).

            Horizontal three-finger swipes will keep working as normal.
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open Trackpad Settings")
            alert.addButton(withTitle: "Later")

            NSApp.activate(ignoringOtherApps: true)
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                let urls = [
                    "x-apple.systempreferences:com.apple.Trackpad-Settings.extension",
                    "x-apple.systempreferences:com.apple.preference.trackpad"
                ]
                for raw in urls {
                    if let url = URL(string: raw), NSWorkspace.shared.open(url) {
                        break
                    }
                }
            }

            self.settings.hasShownFirstRunGuide = true
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
