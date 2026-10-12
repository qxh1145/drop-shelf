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

    nonisolated private static let fileDragTypes: Set<NSPasteboard.PasteboardType> = Set(
        [.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map {
            NSPasteboard.PasteboardType($0)
        }
    )
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
    private let dragPasteboard = NSPasteboard(name: .drag)
    private var dragChangeCountAtMouseDown = 0
    private var isFileDrag = false

    // AppKit owns these opaque tokens; every mutation happens on MainActor.
    // Unsafe nonisolation only permits deterministic cleanup from deinit.
    nonisolated(unsafe) private var globalMonitor: Any?
    private var onShake: (() -> Void)?
    private var isStarted = false

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
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

        installGlobalMonitorIfNeeded()
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

    private func installGlobalMonitorIfNeeded() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged]
        ) { [weak self] event in
            guard let self else { return }

            switch event.type {
            case .leftMouseDown:
                self.resetGestureState()
                self.dragChangeCountAtMouseDown = self.dragPasteboard.changeCount
                self.isFileDrag = false
            case .leftMouseDragged:
                // Any app's file drag (Finder, browser downloads, Photos) writes
                // the drag pasteboard; plain drags (text selection, window
                // moves) never do, so they cannot trigger the shelf.
                guard self.updateIsFileDrag() else { return }
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

    private func updateIsFileDrag() -> Bool {
        let changeCount = dragPasteboard.changeCount
        if !isFileDrag, changeCount != dragChangeCountAtMouseDown {
            // Inspect each pasteboard write once, not on every drag event.
            dragChangeCountAtMouseDown = changeCount
            isFileDrag = !Self.fileDragTypes.isDisjoint(with: dragPasteboard.types ?? [])
        }
        return isFileDrag
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
