import AppKit
import LidBlurCore
import QuartzCore

/// Drives the overlay: reads the lid angle (or lid events), animates the blur strength and
/// adapts its polling rate so it costs next to nothing while the lid is not moving.
@MainActor
final class LidBlurController: NSObject {
    private struct Segment {
        /// Target strength, or nil to animate towards whatever the lid angle asks for.
        let to: Double?
        let duration: Double
        let easing: (Double) -> Double
    }

    private struct RunningSegment {
        let segment: Segment
        let from: Double
        let start: CFTimeInterval
    }

    private let settings = Settings.shared
    private let overlay = BlurOverlay()
    private var sensor: LidAngleSensor?
    private var curve = BlurCurve()

    private(set) var currentAngle: Double?
    private var target = 0.0
    private var current = 0.0
    private var queue: [Segment] = []
    private var running: RunningSegment?

    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var lastTick = CACurrentMediaTime()
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
        curve = BlurCurve(closedAngle: 10, clearAngle: settings.clearAngle)
        if settings.enabled {
            schedule(interval: 1.0 / 60)
        } else {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            queue.removeAll()
            running = nil
            current = 0
            overlay.hide()
        }
    }

    /// Blur in, hold, then unfold, so the effect can be tried without moving the lid.
    func preview() {
        guard settings.enabled else { return }
        queue = [
            Segment(to: 1, duration: 0.5, easing: Easing.easeInOutCubic),
            Segment(to: 1, duration: 0.3, easing: Easing.smoothstep),
            Segment(to: nil, duration: 0.6, easing: Easing.easeOutCubic),
        ]
        running = nil
        schedule(interval: 1.0 / 60)
    }

    // MARK: - Lid events

    @objc private func goingDark() {
        guard settings.enabled else { return }
        // Cover the screen before it lights up again, so the first frame after waking is blurred.
        queue.removeAll()
        running = nil
        current = 1
        render()
    }

    @objc private func wokeUp() {
        guard settings.enabled else { return }
        if sensor == nil || sensor?.readAngle() == nil { sensor = LidAngleSensor() }
        unfold()
    }

    private func unfold() {
        if let running, running.segment.to == nil { return }
        current = max(current, 1)
        queue = [Segment(to: nil, duration: 0.6, easing: Easing.easeOutCubic)]
        running = nil
        schedule(interval: 1.0 / 60)
    }

    // MARK: - Frame loop

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTick)
        lastTick = now

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
        } else {
            current = Easing.approach(current, target, dt: dt, timeConstant: 0.07)
        }

        render()

        let animating = running != nil || !queue.isEmpty || abs(current - target) > 0.001
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
        if let angle = sensor.readAngle() {
            readFailures = 0
            if let previous = currentAngle, abs(previous - angle) < 1 {
                // unchanged
            } else {
                lastAngleChange = now
            }
            currentAngle = angle
            target = curve.strength(forAngle: angle)
        } else {
            readFailures += 1
            if readFailures > 60 {
                // The device can disappear across sleep. Try to find it again, else fall back.
                readFailures = 0
                currentAngle = nil
                self.sensor = LidAngleSensor()
            }
        }
    }

    private func pollClamshell(now: CFTimeInterval) {
        guard now - lastClamshellCheck >= 0.5 else { return }
        lastClamshellCheck = now
        let closed = Clamshell.isClosed()
        defer { lidClosed = closed }
        guard let closed, let wasClosed = lidClosed, closed != wasClosed else { return }
        if closed {
            target = 1
        } else {
            target = 0
            unfold()
        }
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
