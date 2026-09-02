import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences

    private var appIcon: NSImage {
        if let icon = NSImage(named: "AppIconImage") {
            return icon
        }
        if let icon = Bundle.main.image(forResource: "AppIcon") {
            return icon
        }
        if let iconName = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
           let icon = Bundle.main.image(forResource: iconName) {
            return icon
        }
        let bundlePath = Bundle.main.bundlePath
        if !bundlePath.isEmpty {
            return NSWorkspace.shared.icon(forFile: bundlePath)
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("DropShelf")
                        .font(.title2.weight(.semibold))
                    Text("Settings")
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(
                        "Launch DropShelf at login",
                        isOn: Binding(
                            get: { preferences.launchAtLoginEnabled },
                            set: { preferences.setLaunchAtLogin($0) }
                        )
                    )
                    .toggleStyle(.switch)

                    if let statusMessage = preferences.loginItemStatusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(
                                preferences.loginItemError == nil ? Color.secondary : Color.red
                            )
                    } else {
                        Text("Keeps DropShelf available from the menu bar after you sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            } label: {
                Label("General", systemImage: "gearshape")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Shake sensitivity")
                        Spacer()
                        Text(preferences.sensitivityLabel)
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { preferences.shakeSensitivity },
                            set: { preferences.setShakeSensitivity($0) }
                        ),
                        in: 0...1,
                        step: 0.05
                    )

                    HStack {
                        Text("Less sensitive")
                        Spacer()
                        Text("More sensitive")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 3)
            } label: {
                Label("Gesture", systemImage: "cursorarrow.motionlines")
            }
        }
        .padding(24)
        .frame(width: 460, height: 330)
    }
}
