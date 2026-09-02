import AppKit

@MainActor
final class ShakeDetector {
    struct Configuration {
        var sampleWindow: TimeInterval
        var minimumLegDistance: CGFloat
        var minimumDirectionChanges: Int
        var minimumTotalTravel: CGFloat
        var cooldown: TimeInterval

        init(sensitivity: Double) {
            let value = min(max(sensitivity, 0), 1)
            sampleWindow = 0.5 + (0.3 * value)
            minimumLegDistance = 36 - (18 * value)
            minimumDirectionChanges = 3
            minimumTotalTravel = 180 - (90 * value)
            cooldown = 0.8
        }

        static let standard = Configuration(sensitivity: 0.5)
    }

    static let shared = ShakeDetector()

    nonisolated private static let finderBundleIdentifier = "com.apple.finder"
    nonisolated private static let minimumSampleInterval: TimeInterval = 1.0 / 120.0

    private var configuration: Configuration
    private var candidateStartTime: TimeInterval?
    private var lastAcceptedSampleTime = -TimeInterval.infinity
    private var anchorX: CGFloat = 0
    private var extremeX: CGFloat = 0
    private var direction = 0
    private var directionChanges = 0
    private var completedTravel: CGFloat = 0
    private var lastTriggerTime = -TimeInterval.infinity

    // AppKit owns these opaque tokens; every mutation happens on MainActor.
    // Unsafe nonisolation only permits deterministic cleanup from deinit.
    nonisolated(unsafe) private var globalMonitor: Any?
    nonisolated(unsafe) private var activationObserver: NSObjectProtocol?
    private var onShake: (() -> Void)?
    private var isStarted = false

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    func updateSensitivity(_ sensitivity: Double) {
        configuration = Configuration(sensitivity: sensitivity)
        resetGestureState()
    }

    func start(onShake: @escaping () -> Void) {
        stop()
        self.onShake = onShake
        isStarted = true

        let workspace = NSWorkspace.shared
        activationObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: workspace,
            queue: .main
        ) { [weak self] notification in
            let activatedBundleIdentifier = (
                notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            )?.bundleIdentifier

            // NotificationCenter's closure is not actor-annotated even with a
            // main queue. Hop once per app activation, never per mouse event.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let activatedBundleIdentifier {
                    self.setFinderActive(
                        activatedBundleIdentifier == Self.finderBundleIdentifier
                    )
                } else {
                    self.reconcileFrontmostApplication()
                }
            }
        }

        // Observe first, then take a snapshot so an activation cannot be missed
        // between the initial state check and observer registration.
        reconcileFrontmostApplication()
    }

    func stop() {
        stopOnMain()
    }

    func reset() {
        resetGestureState()
    }

    @discardableResult
    func process(point: CGPoint, timestamp: TimeInterval) -> Bool {
        processOnMain(point: point, timestamp: timestamp)
    }

    private func processOnMain(point: CGPoint, timestamp: TimeInterval) -> Bool {
        guard point.x.isFinite, timestamp.isFinite else {
            resetGestureState()
            return false
        }

        if timestamp < lastAcceptedSampleTime {
            resetGestureState()
        }

        guard timestamp - lastTriggerTime >= configuration.cooldown else {
            return false
        }

        guard timestamp - lastAcceptedSampleTime >= Self.minimumSampleInterval else {
            return false
        }
        lastAcceptedSampleTime = timestamp

        guard let candidateStartTime else {
            beginCandidate(at: point.x, timestamp: timestamp)
            return false
        }

        guard timestamp - candidateStartTime <= configuration.sampleWindow else {
            beginCandidate(at: point.x, timestamp: timestamp)
            return false
        }

        updateMetrics(with: point.x)

        let totalTravel = completedTravel + abs(extremeX - anchorX)
        guard directionChanges >= configuration.minimumDirectionChanges,
              totalTravel >= configuration.minimumTotalTravel else {
            return false
        }

        lastTriggerTime = timestamp
        resetGestureState()
        return true
    }

    private func beginCandidate(at x: CGFloat, timestamp: TimeInterval) {
        candidateStartTime = timestamp
        anchorX = x
        extremeX = x
        direction = 0
        directionChanges = 0
        completedTravel = 0
    }

    private func updateMetrics(with x: CGFloat) {
        if direction == 0 {
            let delta = x - anchorX
            if abs(delta) >= configuration.minimumLegDistance {
                direction = delta > 0 ? 1 : -1
                extremeX = x
            }
            return
        }

        if direction > 0 {
            if x > extremeX {
                extremeX = x
            } else if extremeX - x >= configuration.minimumLegDistance {
                completedTravel += abs(extremeX - anchorX)
                directionChanges += 1
                anchorX = extremeX
                extremeX = x
                direction = -1
            }
        } else if x < extremeX {
            extremeX = x
        } else if x - extremeX >= configuration.minimumLegDistance {
            completedTravel += abs(extremeX - anchorX)
            directionChanges += 1
            anchorX = extremeX
            extremeX = x
            direction = 1
        }
    }

    private func reconcileFrontmostApplication() {
        setFinderActive(
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                == Self.finderBundleIdentifier
        )
    }

    private func setFinderActive(_ isFinderActive: Bool) {
        guard isStarted else { return }

        if isFinderActive {
            installGlobalMonitorIfNeeded()
        } else {
            removeGlobalMonitor()
        }
    }

    private func installGlobalMonitorIfNeeded() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged]
        ) { [weak self] event in
            guard let self else { return }

            switch event.type {
            case .leftMouseDown:
                self.resetGestureState()
            case .leftMouseDragged:
                if self.processOnMain(
                    point: event.locationInWindow,
                    timestamp: event.timestamp
                ) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isStarted else { return }
                        self.onShake?()
                    }
                }
            default:
                break
            }
        }
    }

    private func removeGlobalMonitor() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }

        resetGestureState()
    }

    private func stopOnMain() {
        isStarted = false
        removeGlobalMonitor()

        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
            self.activationObserver = nil
        }

        onShake = nil
    }

    private func resetGestureState() {
        candidateStartTime = nil
        lastAcceptedSampleTime = -TimeInterval.infinity
        anchorX = 0
        extremeX = 0
        direction = 0
        directionChanges = 0
        completedTravel = 0
    }

}
