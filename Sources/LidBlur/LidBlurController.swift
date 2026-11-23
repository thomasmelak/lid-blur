import AppKit
import LidBlurCore
import QuartzCore

/// Drives the overlay. The lid angle (or a lid/wake event on Macs without the sensor) is only a
/// trigger: crossing the open angle starts a timed, eased animation to sharp, and closing starts
/// one back to blurred. So however fast the lid moves, the screen always eases into sharpness.
@MainActor
final class LidBlurController: NSObject {
    private struct Segment {
        /// Target fold amount, or nil to animate towards the lid's current state.
        let to: Double?
        let duration: Double
        let easing: (Double) -> Double
    }

    private struct RunningSegment {
        let segment: Segment
        let from: Double
        let start: CFTimeInterval
    }

    /// Lid opened: ease out of the blur, quickly at first, settling gently into sharpness.
    static let clearDuration = 0.9
    /// Lid closing: ease into the blur.
    static let blurDuration = 0.45

    private let settings = Settings.shared
    private let overlay = BlurOverlay()
    private var sensor: LidAngleSensor?
    private var trigger = LidTrigger()

    private(set) var currentAngle: Double?
    /// Where the animation is heading: 0 = open and sharp, 1 = closed and blurred.
    private var target = 0.0
    /// Current fold amount shown on screen.
    private var current = 0.0
    private var queue: [Segment] = []
    private var running: RunningSegment?

    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastAngleChange = -Double.infinity
    private var readFailures = 0
    private var lidClosed: Bool?
    private var lastClamshellCheck = -Double.infinity

    var hasSensor: Bool { sensor != nil }

    func start() {
        sensor = LidAngleSensor()
        lidClosed = Clamshell.isClosed()

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(goingDark),
                           name: NSWorkspace.screensDidSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(goingDark),
                           name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(wokeUp),
                           name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(wokeUp),
                           name: NSWorkspace.didWakeNotification, object: nil)

        settingsChanged()
    }

    func settingsChanged() {
        trigger.openAngle = settings.clearAngle
        trigger.reset()
        if settings.enabled {
            schedule(interval: 1.0 / 60)
        } else {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            queue.removeAll()
            running = nil
            current = 0
            target = 0
            overlay.hide()
        }
    }

    /// Blur in, hold, then ease back out, so the effect can be tried without moving the lid.
    func preview() {
        guard settings.enabled else { return }
        queue = [
            Segment(to: 1, duration: LidBlurController.blurDuration, easing: Easing.easeInOutCubic),
            Segment(to: 1, duration: 0.3, easing: Easing.smoothstep),
            Segment(to: nil, duration: LidBlurController.clearDuration, easing: Easing.easeOutCubic),
        ]
        running = nil
        schedule(interval: 1.0 / 60)
    }

    // MARK: - Triggers

    private func lidOpened() {
        target = 0
        animate(to: 0, duration: LidBlurController.clearDuration, easing: Easing.easeOutCubic)
    }

    private func lidClosing() {
        target = 1
        animate(to: 1, duration: LidBlurController.blurDuration, easing: Easing.easeInOutCubic)
    }

    /// Starts from wherever the screen is now. The duration shrinks with the distance left,
    /// so reversing halfway keeps the same pace instead of crawling.
    private func animate(to value: Double, duration: Double, easing: @escaping (Double) -> Double) {
        let distance = abs(value - current)
        guard distance > 0.001 else {
            queue.removeAll()
            running = nil
            current = value
            return
        }
        queue = [Segment(to: value, duration: duration * max(distance, 0.35), easing: easing)]
        running = nil
        schedule(interval: 1.0 / 60)
    }

    @objc private func goingDark() {
        guard settings.enabled else { return }
        // Cover the screen before it lights up again, so the first frame after waking is blurred.
        queue.removeAll()
        running = nil
        current = 1
        target = 1
        trigger.reset()
        render()
    }

    @objc private func wokeUp() {
        guard settings.enabled else { return }
        if sensor == nil || sensor?.readAngle() == nil { sensor = LidAngleSensor() }
        if sensor == nil {
            // No angle to wait for: waking up is the trigger.
            lidOpened()
        } else {
            // The next reading decides: open past the trigger angle clears, otherwise stays blurred.
            trigger.reset()
            schedule(interval: 1.0 / 60)
        }
    }

    // MARK: - Frame loop

    @objc private func tick() {
        let now = CACurrentMediaTime()

        if sensor != nil {
            readSensor(now: now)
        } else {
            pollClamshell(now: now)
        }

        if running == nil, !queue.isEmpty {
            running = RunningSegment(segment: queue.removeFirst(), from: current, start: now)
        }
        if let run = running {
            let t = Easing.clamp((now - run.start) / max(run.segment.duration, 0.001))
            let end = run.segment.to ?? target
            current = run.from + (end - run.from) * run.segment.easing(t)
            if t >= 1 { running = nil }
        }

        render()

        let animating = running != nil || !queue.isEmpty
        let lidMoving = now - lastAngleChange < 1.5
        if animating || lidMoving {
            schedule(interval: 1.0 / 60)
        } else {
            schedule(interval: sensor != nil ? 1.0 / 10 : 1.0 / 2)
        }
    }

    private func render() {
        overlay.apply(strength: current, style: settings.style, maxOpacity: settings.intensity.maxOpacity)
    }

    private func readSensor(now: CFTimeInterval) {
        guard let sensor else { return }
        guard let angle = sensor.readAngle() else {
            readFailures += 1
            if readFailures > 60 {
                // The device can disappear across sleep. Try to find it again, else fall back.
                readFailures = 0
                currentAngle = nil
                self.sensor = LidAngleSensor()
            }
            return
        }
        readFailures = 0
        if currentAngle.map({ abs($0 - angle) >= 1 }) ?? true { lastAngleChange = now }
        currentAngle = angle

        switch trigger.update(angle: angle) {
        case true?: lidOpened()
        case false?: lidClosing()
        case nil: break
        }
    }

    private func pollClamshell(now: CFTimeInterval) {
        guard now - lastClamshellCheck >= 0.5 else { return }
        lastClamshellCheck = now
        let closed = Clamshell.isClosed()
        defer { lidClosed = closed }
        guard let closed, let wasClosed = lidClosed, closed != wasClosed else { return }
        if closed { lidClosing() } else { current = max(current, 1); lidOpened() }
    }

    private func schedule(interval: TimeInterval) {
        guard settings.enabled else { return }
        if timer != nil, timerInterval == interval { return }
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = interval * 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        timerInterval = interval
    }
}
