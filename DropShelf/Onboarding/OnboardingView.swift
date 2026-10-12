import AppKit
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var preferences: AppPreferences
    let finish: () -> Void

    @State private var step: Step = .welcome

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ZStack {
                stepContent
                    .id(step)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            Divider()
            footer
        }
        .frame(width: 660, height: 480)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: appIcon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("DropShelf")
                    .font(.system(size: 15, weight: .semibold))
                Text("Getting Started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 7) {
                ForEach(Step.allCases) { item in
                    Circle()
                        .fill(item == step ? Color.accentColor : Color.secondary.opacity(0.22))
                        .frame(width: item == step ? 9 : 7, height: item == step ? 9 : 7)
                        .accessibilityLabel(item.title)
                }
            }
        }
        .padding(.horizontal, 24)
        // Clear the traffic-light buttons drawn over the transparent titlebar.
        .padding(.top, 32)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            welcomeStep
        case .practice:
            practiceStep
        case .ready:
            readyStep
        }
    }

    private var welcomeStep: some View {
        OnboardingPage(
            symbol: "tray.and.arrow.down.fill",
            title: "Move files without breaking your flow",
            subtitle: "DropShelf creates a temporary floating shelf while you drag files in Finder. It keeps references only—your files stay exactly where they are."
        ) {
            HStack(spacing: 14) {
                FeatureCard(
                    symbol: "waveform.path",
                    title: "Shake to open",
                    detail: "Shake left and right while dragging."
                )
                FeatureCard(
                    symbol: "square.stack.3d.up.fill",
                    title: "Collect files",
                    detail: "Add files and folders to one shelf."
                )
                FeatureCard(
                    symbol: "arrow.up.forward.app.fill",
                    title: "Drop anywhere",
                    detail: "Drag them back to Finder together."
                )
            }
        }
    }

    private var practiceStep: some View {
        OnboardingPage(
            symbol: "hand.draw.fill",
            title: "Practice the shake",
            subtitle: "Hold and drag the sample file left and right a few times. This uses the same motion you will make while dragging a real file in Finder."
        ) {
            ShakePracticeView(sensitivity: preferences.shakeSensitivity)
        }
    }

    private var readyStep: some View {
        OnboardingPage(
            symbol: "checkmark.circle.fill",
            symbolColor: .green,
            title: "You’re ready",
            subtitle: "DropShelf stays available from the menu bar and uses almost no CPU while idle."
        ) {
            VStack(spacing: 12) {
                ReadyRow(
                    symbol: "waveform.path",
                    title: "Shake while dragging",
                    detail: preferences.shakeGestureEnabled ? "Enabled" : "Disabled in Settings"
                )
                ReadyRow(
                    symbol: "keyboard",
                    title: "Open Shelf",
                    detail: preferences.activationShortcutError == nil
                        ? LocalizedStringKey(preferences.activationShortcut.displayName)
                        : "Unavailable — change in Settings"
                )
                ReadyRow(
                    symbol: "clock.arrow.circlepath",
                    title: "Recent Shelves",
                    detail: "⌘⇧H"
                )
            }
            .frame(maxWidth: 430)
        }
    }

    private var footer: some View {
        HStack {
            Button("Skip") {
                finish()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            if step != .welcome {
                Button("Back") {
                    move(to: step.previous)
                }
                .keyboardShortcut(.leftArrow, modifiers: [])
            }

            Button(step == .ready ? "Start Using DropShelf" : "Continue") {
                if step == .ready {
                    finish()
                } else {
                    move(to: step.next)
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24)
        .frame(height: 58)
    }

    private var appIcon: NSImage {
        if let icon = NSImage(named: "AppIconImage") {
            return icon
        }
        return NSApp.applicationIconImage
    }

    private func move(to newStep: Step) {
        withAnimation(.easeOut(duration: 0.18)) {
            step = newStep
        }
    }
}

private extension OnboardingView {
    enum Step: Int, CaseIterable, Identifiable {
        case welcome
        case practice
        case ready

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .welcome: String(localized: "Welcome")
            case .practice: String(localized: "Practice")
            case .ready: String(localized: "Ready")
            }
        }

        var next: Step {
            Step(rawValue: rawValue + 1) ?? self
        }

        var previous: Step {
            Step(rawValue: rawValue - 1) ?? self
        }
    }
}

private struct OnboardingPage<Content: View>: View {
    let symbol: String
    var symbolColor: Color = .accentColor
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    @ViewBuilder let content: Content

    init(
        symbol: String,
        symbolColor: Color = .accentColor,
        title: LocalizedStringKey,
        subtitle: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) {
        self.symbol = symbol
        self.symbolColor = symbolColor
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 38, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)

            VStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 23, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(maxWidth: 500)
            }

            content
        }
        .padding(.horizontal, 34)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FeatureCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 83, alignment: .topLeading)
        .padding(13)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

private struct ShakePracticeView: View {
    // Same detector and thresholds as the real Finder gesture, so passing the
    // practice means the shake will also work while dragging a real file.
    @State private var detector: ShakeDetector
    @State private var horizontalOffset: CGFloat = 0
    @State private var completed = false

    init(sensitivity: Double) {
        _detector = State(
            initialValue: ShakeDetector(
                configuration: .init(sensitivity: sensitivity)
            )
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
                    .frame(width: 390, height: 8)

                HStack(spacing: 6) {
                    Image(systemName: completed ? "checkmark.circle.fill" : "doc.fill")
                    Text(completed ? "Great—that’s the gesture" : "sample-file.pdf")
                        .lineLimit(1)
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(completed ? Color.green : Color.primary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                .offset(x: horizontalOffset)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged(handleDrag)
                        .onEnded { _ in
                            withAnimation(.easeOut(duration: 0.16)) {
                                horizontalOffset = 0
                            }
                            detector.reset()
                        }
                )
                .help("Drag left and right")
            }
            .frame(height: 64)

            Text(completed ? "Now do this while dragging a file in Finder." : "Drag quickly left ↔ right a few times")
                .font(.caption)
                .foregroundStyle(completed ? Color.green : Color.secondary)
        }
    }

    private func handleDrag(_ value: DragGesture.Value) {
        guard !completed else { return }

        let x = value.translation.width
        horizontalOffset = min(max(x, -150), 150)

        if detector.process(
            point: CGPoint(x: x, y: 0),
            timestamp: value.time.timeIntervalSinceReferenceDate
        ) {
            completed = true
            horizontalOffset = 0
        }
    }
}

private struct ReadyRow: View {
    let symbol: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .frame(width: 24)
                .foregroundStyle(Color.accentColor)
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Spacer()
            Text(detail)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
    }
}
