import AppKit
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
        VStack(alignment: .leading, spacing: 16) {
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

                    Toggle(
                        "Show DropShelf in Dock",
                        isOn: Binding(
                            get: { preferences.showInDock },
                            set: { preferences.setShowInDock($0) }
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
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Enable shake gesture",
                        isOn: Binding(
                            get: { preferences.shakeGestureEnabled },
                            set: { preferences.setShakeGestureEnabled($0) }
                        )
                    )
                    .toggleStyle(.checkbox)

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
                    .disabled(!preferences.shakeGestureEnabled)

                    HStack {
                        Text("Less sensitive")
                        Spacer()
                        Text("More sensitive")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Divider()

                    HStack {
                        Text("Open Shelf shortcut")
                        Spacer()
                        ShortcutRecorder(
                            shortcut: preferences.activationShortcut,
                            onChange: preferences.setActivationShortcut
                        )
                        .frame(width: 150, height: 26)
                    }

                    if let shortcutError = preferences.activationShortcutError {
                        Text(shortcutError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else {
                        Text("Click the shortcut, then press a new key combination.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            } label: {
                Label("Gesture", systemImage: "cursorarrow.motionlines")
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(
                        "Close shelf when empty",
                        isOn: Binding(
                            get: { preferences.closeShelfWhenEmpty },
                            set: { preferences.setCloseShelfWhenEmpty($0) }
                        )
                    )
                    .toggleStyle(.checkbox)

                    Toggle(
                        "Automatically hide after 10 seconds",
                        isOn: Binding(
                            get: { preferences.automaticallyHideAfterTenSeconds },
                            set: { preferences.setAutomaticallyHideAfterTenSeconds($0) }
                        )
                    )
                    .toggleStyle(.checkbox)

                    Text("Auto-hide keeps the current files and resets after Shelf activity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 3)
            } label: {
                Label("Shelf", systemImage: "tray.full")
            }
        }
        .padding(24)
        .frame(width: 500, height: 570)
    }
}

private struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: ShelfActivationShortcut
    let onChange: (ShelfActivationShortcut) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        ShortcutRecorderButton(shortcut: shortcut, onChange: onChange)
    }

    func updateNSView(_ nsView: ShortcutRecorderButton, context: Context) {
        nsView.update(shortcut: shortcut, onChange: onChange)
    }
}

private final class ShortcutRecorderButton: NSButton {
    private var shortcut: ShelfActivationShortcut
    private var onChange: (ShelfActivationShortcut) -> Void
    private var isRecordingShortcut = false

    init(
        shortcut: ShelfActivationShortcut,
        onChange: @escaping (ShelfActivationShortcut) -> Void
    ) {
        self.shortcut = shortcut
        self.onChange = onChange
        super.init(frame: .zero)

        bezelStyle = .rounded
        controlSize = .regular
        font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        target = self
        action = #selector(toggleRecording)
        toolTip = "Click, then type a keyboard shortcut"
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    func update(
        shortcut: ShelfActivationShortcut,
        onChange: @escaping (ShelfActivationShortcut) -> Void
    ) {
        self.shortcut = shortcut
        self.onChange = onChange
        if !isRecordingShortcut {
            updateTitle()
        }
    }

    override func keyDown(with event: NSEvent) {
        guard isRecordingShortcut else {
            super.keyDown(with: event)
            return
        }
        capture(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecordingShortcut else {
            return super.performKeyEquivalent(with: event)
        }
        capture(event)
        return true
    }

    override func resignFirstResponder() -> Bool {
        let didResign = super.resignFirstResponder()
        if didResign, isRecordingShortcut {
            finishRecording()
        }
        return didResign
    }

    override func cancelOperation(_ sender: Any?) {
        finishRecording()
    }

    @objc private func toggleRecording() {
        if isRecordingShortcut {
            finishRecording()
        } else {
            isRecordingShortcut = true
            title = "Type shortcut…"
            window?.makeFirstResponder(self)
        }
    }

    private func capture(_ event: NSEvent) {
        if event.keyCode == 53 {
            finishRecording()
            return
        }

        guard let recordedShortcut = ShelfActivationShortcut(event: event) else {
            NSSound.beep()
            title = "Add a modifier…"
            return
        }

        shortcut = recordedShortcut
        onChange(recordedShortcut)
        finishRecording()
    }

    private func finishRecording() {
        isRecordingShortcut = false
        updateTitle()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
    }

    private func updateTitle() {
        title = shortcut.displayName
        setAccessibilityLabel("Open Shelf shortcut: \(shortcut.displayName)")
    }
}
