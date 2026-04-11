import SwiftUI

/// Grindow — 2D Space Grid Navigation for macOS
///
/// This app extends macOS Spaces into a 2D grid, enabling vertical
/// navigation via three-finger swipes on the trackpad. It intercepts
/// the default three-finger up/down swipe gestures (Mission Control
/// and App Exposé) and replaces them with Space switching in a
/// configurable grid layout.
@main
struct GrindowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar app — no main window scene
        Settings {
            EmptyView()
        }
    }
}
