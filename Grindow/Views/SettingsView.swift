import SwiftUI

/// Settings panel for configuring Grindow behavior.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

    @ObservedObject private var permissions = AccessibilityHelper.shared

    var body: some View {
        Form {
            Section("Gesture Behavior") {
                Picker("Edge Behavior:", selection: $settings.edgeBehavior) {
                    ForEach(EdgeBehavior.allCases, id: \.self) { behavior in
                        VStack(alignment: .leading) {
                            Text(behavior.displayName)
                        }
                        .tag(behavior)
                    }
                }
                .pickerStyle(.radioGroup)

                Text(settings.edgeBehavior.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)

                if settings.edgeBehavior == .bounce {
                    Toggle("Show bounce animation overlay", isOn: $settings.showBounceAnimation)
                        .padding(.leading, 20)
                }

                Toggle("Invert all swipe directions", isOn: $settings.invertSwipes)
                Text("Reverse both horizontal and vertical swipes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 20)
            }

            Divider()

            Section("Space Switching") {
                Toggle("Show grid after swiping", isOn: $settings.showSwipeGrid)
                Text("Briefly show your position without interrupting typing or clicks.")
                    .font(.caption).foregroundColor(.secondary)
                Picker("Animation", selection: $settings.transitionSpeed) {
                    ForEach(TransitionSpeed.allCases, id: \.self) { speed in
                        Text(speed.rawValue.capitalized).tag(speed)
                    }
                }
                Text("Animations move horizontally. Longer grid jumps use instant switching.")
                    .font(.caption).foregroundColor(.secondary)
                Text(permissions.isGranted ? "Accessibility access enabled" : "Accessibility access required")
                Button("Open Accessibility Settings…") { permissions.requestAccessibility() }
                Text("In Trackpad settings, turn off three-finger Space switching, Mission Control, and App Exposé, or assign them to four fingers.")
                    .font(.caption).foregroundColor(.secondary)
            }

            Section("General") {
                Toggle("Enable Grindow", isOn: $settings.isEnabled)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Divider()

            Section("Info") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Grindow extends macOS Spaces into a 2D grid.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Three-finger vertical swipes navigate between rows.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("Horizontal swipes navigate columns. Each display keeps its own grid.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            HStack {
                Button("Reset to Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 420, minHeight: 380)
    }
}
