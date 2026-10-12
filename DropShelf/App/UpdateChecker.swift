import AppKit

/// Looks for a newer GitHub release and offers its download page. DropShelf
/// isn't signed with a Developer ID, so updates are installed by hand.
@MainActor
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/qxh1145/drop-shelf/releases/latest"
    )!
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

    private enum Keys {
        static let lastCheck = "DropShelf.lastUpdateCheck"
        static let skippedVersion = "DropShelf.skippedUpdateVersion"
    }

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case body
        }
    }

    private let defaults: UserDefaults
    private var isChecking = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    func checkAutomaticallyIfNeeded() {
        guard AppPreferences.shared.checkForUpdatesAutomatically else { return }
        if let lastCheck = defaults.object(forKey: Keys.lastCheck) as? Date,
           Date().timeIntervalSince(lastCheck) < Self.automaticCheckInterval {
            return
        }
        check(userInitiated: false)
    }

    func check(userInitiated: Bool) {
        guard !isChecking else { return }
        isChecking = true

        Task {
            defer { isChecking = false }
            do {
                var request = URLRequest(url: Self.latestReleaseURL, timeoutInterval: 15)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                defaults.set(Date(), forKey: Keys.lastCheck)

                // 404 means no release has been published yet.
                guard status != 404 else {
                    if userInitiated { showUpToDate() }
                    return
                }
                guard status == 200 else { throw URLError(.badServerResponse) }

                present(try JSONDecoder().decode(Release.self, from: data), userInitiated: userInitiated)
            } catch {
                guard userInitiated else { return }
                showAlert(
                    title: String(localized: "Couldn’t check for updates"),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func present(_ release: Release, userInitiated: Bool) {
        guard UpdateVersion.isNewer(release.tagName, than: currentVersion) else {
            if userInitiated { showUpToDate() }
            return
        }
        if !userInitiated, defaults.string(forKey: Keys.skippedVersion) == release.tagName {
            return
        }

        let alert = NSAlert()
        let newVersion = UpdateVersion.displayString(release.tagName)
        alert.messageText = String(localized: "DropShelf \(newVersion) is available")
        var message = String(localized: "You have version \(currentVersion).")
        if let notes = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            message += "\n\n" + String(notes.prefix(600))
        }
        alert.informativeText = message
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))
        alert.addButton(withTitle: String(localized: "Skip This Version"))

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.htmlURL)
        case .alertThirdButtonReturn:
            defaults.set(release.tagName, forKey: Keys.skippedVersion)
        default:
            break
        }
    }

    private func showUpToDate() {
        showAlert(
            title: String(localized: "You’re up to date"),
            message: String(localized: "DropShelf \(currentVersion) is the latest version.")
        )
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

enum UpdateVersion {
    /// "v1.10.2" → [1, 10, 2]; anything after a "-" (pre-release) is ignored.
    static func components(_ version: String) -> [Int] {
        displayString(version)
            .split(separator: "-", maxSplits: 1).first
            .map { $0.split(separator: ".").map { Int($0) ?? 0 } } ?? []
    }

    static func displayString(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let lhs = components(candidate)
        let rhs = components(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let left = index < lhs.count ? lhs[index] : 0
            let right = index < rhs.count ? rhs[index] : 0
            if left != right { return left > right }
        }
        return false
    }
}
