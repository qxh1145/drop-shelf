import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var preferences: AppPreferences
    @State private var selectedSection: SettingsSection = .general

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
        HStack(spacing: 0) {
            settingsSidebar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(selectedSection.title)
                        .font(.title2.weight(.semibold))
                    Text(selectedSection.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    selectedSectionContent
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)
            }
        }
        .frame(width: 650, height: 470)
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text("DropShelf")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)

            VStack(spacing: 3) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selectedSection = section
                    } label: {
                        Label(section.title, systemImage: section.symbol)
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .frame(height: 31)
                            .background(
                                selectedSection == section
                                    ? Color.accentColor.opacity(0.18)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            Spacer()

            Text(versionText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
        }
        .padding(14)
        .frame(width: 172)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var selectedSectionContent: some View {
        switch selectedSection {
        case .general:
            generalSettings
        case .activation:
            activationSettings
        case .shelf:
            shelfSettings
        case .history:
            historySettings
        case .about:
            aboutSettings
        }
    }

    private var generalSettings: some View {
        SettingsCard {
            SettingsToggleRow(
                title: "Launch at login",
                description: "Keep DropShelf available from the menu bar after signing in.",
                isOn: Binding(
                    get: { preferences.launchAtLoginEnabled },
                    set: { preferences.setLaunchAtLogin($0) }
                )
            )

            Divider()

            SettingsToggleRow(
                title: "Show in Dock",
                description: "Display DropShelf alongside your other running applications.",
                isOn: Binding(
                    get: { preferences.showInDock },
                    set: { preferences.setShowInDock($0) }
                )
            )

            if let statusMessage = preferences.loginItemStatusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(preferences.loginItemError == nil ? Color.secondary : .red)
            }
        }
    }

    private var activationSettings: some View {
        SettingsCard {
            SettingsToggleRow(
                title: "Shake gesture",
                description: "Open a Shelf by shaking the pointer while dragging files.",
                isOn: Binding(
                    get: { preferences.shakeGestureEnabled },
                    set: { preferences.setShakeGestureEnabled($0) }
                )
            )

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Shake sensitivity")
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(preferences.sensitivityLabel)
                        .font(.caption)
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
                    Text("Low")
                    Spacer()
                    Text("Balanced")
                    Spacer()
                    Text("High")
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Open Shelf shortcut")
                        .font(.system(size: 12, weight: .medium))
                    Text("Click the shortcut, then press a new combination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ShortcutRecorder(
                    shortcut: preferences.activationShortcut,
                    onChange: preferences.setActivationShortcut
                )
                .frame(width: 150, height: 27)
            }

            if let shortcutError = preferences.activationShortcutError {
                Text(shortcutError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var shelfSettings: some View {
        SettingsCard {
            SettingsToggleRow(
                title: "Close when empty",
                description: "Close the Shelf after its final item is removed or dragged out.",
                isOn: Binding(
                    get: { preferences.closeShelfWhenEmpty },
                    set: { preferences.setCloseShelfWhenEmpty($0) }
                )

            )
            Divider()
            SettingsToggleRow(
                title: "Hide after 10 seconds",
                description: "Hide inactive Shelves without removing their current files.",
                isOn: Binding(
                    get: { preferences.automaticallyHideAfterTenSeconds },
                    set: { preferences.setAutomaticallyHideAfterTenSeconds($0) }
                )
            )
        }
    }

    private var historySettings: some View {
        SettingsCard {
            SettingsInfoRow(
                symbol: "clock.arrow.circlepath",
                title: "72-hour history",
                description: "Unpinned Shelves are retained for 72 hours. DropShelf stores file references only."
            )
            Divider()
            SettingsInfoRow(
                symbol: "pin.fill",
                title: "Pinned Shelves",
                description: "Pinned entries do not expire and remain accessible from the menu bar."
            )
            Divider()
            SettingsInfoRow(
                symbol: "keyboard",
                title: "Quick access",
                description: "Press Command–Shift–H to open Recent Shelves."
            )
        }
    }

    private var aboutSettings: some View {
        SettingsCard {
            HStack(spacing: 16) {
                Image(nsImage: appIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 5) {
                    Text("DropShelf")
                        .font(.title3.weight(.semibold))
                    Text(versionText)
                        .foregroundStyle(.secondary)
                    Text("A lightweight temporary Shelf for macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1.2.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String ?? "8"
        return "Version \(version) (\(build))"
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case activation
    case shelf
    case history
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .activation: "Activation"
        case .shelf: "Shelf"
        case .history: "History"
        case .about: "About"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Choose how DropShelf appears and starts."
        case .activation: "Configure how you summon a Shelf."
        case .shelf: "Control Shelf closing and visibility behavior."
        case .history: "Understand recent and pinned Shelf retention."
        case .about: "Version and application information."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .activation: "cursorarrow.motionlines"
        case .shelf: "tray.full"
        case .history: "clock.arrow.circlepath"
        case .about: "info.circle"
        }
    }
}

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

private struct SettingsInfoRow: View {
    let symbol: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
