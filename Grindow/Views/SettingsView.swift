import SwiftUI

/// Settings panel for configuring Grindow behavior.
struct SettingsView: View {
    @ObservedObject var settings: AppSettings

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
            }

            Divider()

            Section("General") {
                Toggle("Enable Grindow", isOn: $settings.isEnabled)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Divider()

            Section("Accessibility") {
                HStack {
                    let granted = AccessibilityHelper.shared.isAccessibilityGranted
                    Circle()
                        .fill(granted ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(granted ? "Accessibility access granted" : "Accessibility access required")
                        .font(.body)

                    Spacer()

                    if !granted {
                        Button("Grant Access") {
                            AccessibilityHelper.shared.requestAccessibility()
                        }
                        .buttonStyle(.bordered)
                    }
                }
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
                    Text("Horizontal swipes work as normal macOS Space switching.")
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
