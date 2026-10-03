import Cocoa
import SwiftUI

/// The main application delegate that coordinates all Grindow components.
///
/// Responsibilities:
/// - Sets up the menu bar status item
/// - Initializes and connects the gesture interceptor, space manager, and grid
/// - Handles swipe events and translates them into space switches
/// - Manages the settings and grid configuration windows
@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Components

    private let spaceManager = SpaceManager.shared
    private let gestureInterceptor = GestureInterceptor.shared
    private let settings = AppSettings.shared
    private let spaceGrid = SpaceGrid()
    private let swipeOverlay = SwipeGridOverlayController()

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
        swipeOverlay.hide()
        spaceManager.cancelSwitching()
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
        spaceManager.onChange = { [weak self] in self?.rebuildGrid() }
        rebuildGrid()
        settings.$gridRows.combineLatest(settings.$gridColumns)
            .debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildGrid() }.store(in: &cancellables)
    }

    private func syncGridToSystem() {
        spaceManager.refreshSpaces()
        rebuildGrid()
    }

    private func rebuildGrid() {
        let ids = spaceManager.spaces.map(\.id)
        let layout = settings.layout(for: spaceManager.selectedDisplayID, liveIDs: ids)
        spaceGrid.arrange(spaceIDs: layout, rows: settings.gridRows, columns: settings.gridColumns)
        spaceGrid.updateCurrentPosition(forSpaceID: spaceManager.activeSpaceID)
        swipeOverlay.update(grid: spaceGrid, manager: spaceManager)
    }

    // MARK: - Gesture Interceptor

    private func setupGestureInterceptor() {
        gestureInterceptor.onSwipe = { [weak self] direction in
            self?.handleSwipe(direction: direction)
        }

        gestureInterceptor.onGestureBegan = { [weak self] in self?.spaceManager.selectCursorDisplay() }
        let permissions = AccessibilityHelper.shared
        permissions.startMonitoring()
        settings.$isEnabled.combineLatest(permissions.$isGranted)
            .receive(on: DispatchQueue.main).sink { [weak self] enabled, granted in
                guard let self else { return }
                if enabled && granted {
                    self.gestureInterceptor.start()
                } else {
                    self.gestureInterceptor.stop()
                    self.spaceManager.cancelSwitching()
                    self.swipeOverlay.hide()
                }
            }.store(in: &cancellables)
        settings.$showSwipeGrid.sink { [weak self] show in
            if !show { self?.swipeOverlay.hide() }
        }.store(in: &cancellables)
    }

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Swipe Handling

    private func handleSwipe(direction: SwipeDirection) {
        guard settings.isEnabled else { return }

        // macOS acts on its own three-finger swipes too; handling this one as
        // well would switch Spaces twice.
        if NativeTrackpadGestures.claims(direction) {
            spaceManager.lastError = nativeGestureConflictMessage(for: direction)
            return
        }

        // Refresh current position from active space
        syncGridToSystem()
        // Repeated swipes route from the pending destination without falsely
        // marking it active in the UI before macOS confirms it.
        let navigationID = spaceManager.navigationSpaceID
        guard let current = spaceGrid.position(forSpaceID: navigationID) else { return }

        let target = spaceGrid.targetPosition(
            from: current,
            direction: direction,
            edgeBehavior: settings.edgeBehavior
        )

        if let targetPosition = target {
            // Valid target — switch to it
            guard let id = spaceGrid.spaceID(at: targetPosition),
                  spaceManager.switchToSpace(id: id) else { return }
        } else {
            // At the edge
            if settings.edgeBehavior == .bounce && settings.showBounceAnimation {
                BounceOverlayController.shared.showBounce(direction: direction)
            }
        }
        if settings.showSwipeGrid {
            swipeOverlay.show(grid: spaceGrid, manager: spaceManager)
        }
    }

    private func nativeGestureConflictMessage(for direction: SwipeDirection) -> String {
        switch direction {
        case .left, .right:
            return "macOS also uses three-finger left/right swipes. In Trackpad settings, turn off \"Swipe between full-screen apps\" or set it to four fingers."
        case .up, .down:
            return "macOS also uses three-finger up/down swipes. In Trackpad settings, turn off Mission Control and App Exposé or set them to four fingers."
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
            Grindow uses three-finger swipes to navigate the grid on the display under your pointer. \
            macOS uses the same gesture for Mission Control and App Exposé by default, \
            so they will fight each other until you turn the built-in versions off.

            In System Settings → Trackpad → More Gestures, set \
            "Swipe between full-screen apps", "Mission Control", and "App Exposé" to "Off" \
            (or switch them to four fingers).

            Enable Accessibility for Grindow in its Settings to allow Space switching.
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
        window.setContentSize(NSSize(width: 480, height: 580))
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
