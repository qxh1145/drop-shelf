import AppKit
import Darwin

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var previousInstanceTerminator: PreviousInstanceTerminator?
    private var didStartApplicationServices = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        if let icon = Bundle.main.image(forResource: "AppIcon") ?? NSImage(named: "AppIconImage") ?? (Bundle.main.bundlePath.isEmpty ? nil : NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)) {
            NSApp.applicationIconImage = icon
        }

        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else {
            return
        }

        replacePreviousInstancesThenStart()
    }

    func applicationWillTerminate(_ notification: Notification) {
        previousInstanceTerminator?.cancel()
        previousInstanceTerminator = nil

        ShakeDetector.shared.stop()

        settingsWindowController?.close()
        settingsWindowController = nil

        menuBarController?.invalidate()
        menuBarController = nil
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func replacePreviousInstancesThenStart() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            startApplicationServices()
            return
        }

        let currentApplication = NSRunningApplication.current
        let currentPID = currentApplication.processIdentifier
        let currentLaunchDate = currentApplication.launchDate ?? Date()
        let previousApplications = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { application in
                SingleInstancePolicy.shouldTerminate(
                    otherPID: application.processIdentifier,
                    otherLaunchDate: application.launchDate ?? .distantPast,
                    currentPID: currentPID,
                    currentLaunchDate: currentLaunchDate
                )
            }

        guard !previousApplications.isEmpty else {
            startApplicationServices()
            return
        }

        let terminator = PreviousInstanceTerminator(applications: previousApplications)
        previousInstanceTerminator = terminator
        terminator.terminate { [weak self] in
            guard let self else { return }
            self.previousInstanceTerminator = nil
            self.startApplicationServices()
        }
    }

    private func startApplicationServices() {
        guard !didStartApplicationServices else { return }
        didStartApplicationServices = true

        menuBarController = MenuBarController { [weak self] in
            self?.showSettings()
        }

        ShakeDetector.shared.updateSensitivity(AppPreferences.shared.shakeSensitivity)

        ShakeDetector.shared.start {
            ShelfManager.shared.showShelf(near: NSEvent.mouseLocation)
        }
    }

    private func showSettings() {
        let controller: SettingsWindowController

        if let settingsWindowController {
            controller = settingsWindowController
        } else {
            controller = SettingsWindowController(preferences: .shared) { [weak self] in
                self?.settingsWindowController = nil
            }
            settingsWindowController = controller
        }

        controller.showSettings()
    }
}

enum SingleInstancePolicy {
    static func shouldTerminate(
        otherPID: pid_t,
        otherLaunchDate: Date,
        currentPID: pid_t,
        currentLaunchDate: Date
    ) -> Bool {
        guard otherPID != currentPID else { return false }

        if otherLaunchDate != currentLaunchDate {
            return otherLaunchDate < currentLaunchDate
        }

        // launchDate has limited precision. When two instances start within
        // the same instant, the newer process normally receives the larger PID.
        return otherPID < currentPID
    }
}

@MainActor
private final class PreviousInstanceTerminator {
    private let applications: [pid_t: NSRunningApplication]
    private var exitSources: [pid_t: any DispatchSourceProcess] = [:]
    private var forceTerminationWorkItem: DispatchWorkItem?
    private var completion: (() -> Void)?

    init(applications: [NSRunningApplication]) {
        self.applications = Dictionary(
            uniqueKeysWithValues: applications.map {
                ($0.processIdentifier, $0)
            }
        )
    }

    func terminate(completion: @escaping () -> Void) {
        self.completion = completion

        for (pid, application) in applications {
            guard !application.isTerminated else { continue }

            let source = DispatchSource.makeProcessSource(
                identifier: pid,
                eventMask: .exit,
                queue: .main
            )
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.applicationDidExit(pid: pid)
                }
            }
            exitSources[pid] = source
            source.resume()
            application.terminate()
        }

        guard !exitSources.isEmpty else {
            finish()
            return
        }

        let forceTerminationWorkItem = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.forceTerminateRemainingApplications()
            }
        }
        self.forceTerminationWorkItem = forceTerminationWorkItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + .milliseconds(750),
            execute: forceTerminationWorkItem
        )
    }

    func cancel() {
        completion = nil
        forceTerminationWorkItem?.cancel()
        forceTerminationWorkItem = nil

        for source in exitSources.values {
            source.cancel()
        }
        exitSources.removeAll(keepingCapacity: false)
    }

    private func forceTerminateRemainingApplications() {
        forceTerminationWorkItem = nil

        for (pid, application) in applications where exitSources[pid] != nil {
            guard !application.isTerminated else {
                applicationDidExit(pid: pid)
                continue
            }

            if !application.forceTerminate() {
                Darwin.kill(pid, SIGKILL)
            }
        }
    }

    private func applicationDidExit(pid: pid_t) {
        guard let source = exitSources.removeValue(forKey: pid) else { return }
        source.cancel()

        if exitSources.isEmpty {
            finish()
        }
    }

    private func finish() {
        forceTerminationWorkItem?.cancel()
        forceTerminationWorkItem = nil

        let completion = completion
        self.completion = nil
        completion?()
    }
}
