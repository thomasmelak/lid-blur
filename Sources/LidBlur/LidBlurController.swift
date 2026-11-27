import AppKit
import LidBlurCore
import QuartzCore

/// Drives the overlay. The blur is tied to the lid angle, but the screen follows that angle
/// through an eased, critically damped spring rather than snapping to it: a slow lid is tracked
/// closely, and a lid opened quickly still glides into sharpness.
@MainActor
final class LidBlurController: NSObject {
    private let settings = Settings.shared
    private let overlay = BlurOverlay()
    private var sensor: LidAngleSensor?
    private var curve = BlurCurve()
    private var latch = OpenLatch()
    private var follower = EasedFollower(value: 0)

    private(set) var currentAngle: Double?
    /// Fold amount the lid asks for: 0 = open and sharp, 1 = closed and blurred.
    private var target = 0.0
    /// While set (preview), overrides the lid until this time.
    private var holdBlurredUntil: CFTimeInterval?

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
            wake()
        } else {
            timer?.invalidate()
            timer = nil
            timerInterval = 0
            holdBlurredUntil = nil
            follower.jump(to: 0)
            overlay.hide()
        }
    }

    /// Blur in, hold, then ease back to whatever the lid says.
    func preview() {
        guard settings.enabled else { return }
        holdBlurredUntil = CACurrentMediaTime() + 0.9
        wake()
    }

    // MARK: - Sleep and wake

    @objc private func goingDark() {
        guard settings.enabled else { return }
        // Cover the screen before it lights up again, so waking eases in from blurred.
        follower.jump(to: 1)
        target = 1
        render()
    }

    @objc private func wokeUp() {
        guard settings.enabled else { return }
        if sensor == nil || sensor?.readAngle() == nil { sensor = LidAngleSensor() }
        if sensor == nil { target = 0 }
        wake()
    }

    // MARK: - Frame loop

    private func wake() {
        lastTick = CACurrentMediaTime()
        schedule(interval: 1.0 / 60)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTick)
        lastTick = now

        if sensor != nil {
            readSensor(now: now)
        } else {
            pollClamshell(now: now)
        }

        var goal = target
        if let until = holdBlurredUntil {
            if now < until { goal = 1 } else { holdBlurredUntil = nil }
        }
        follower.step(towards: goal, dt: dt)

        render()

        let settled = follower.value == goal && follower.velocity == 0
        let lidMoving = now - lastAngleChange < 1.5
        if !settled || lidMoving || holdBlurredUntil != nil {
            schedule(interval: 1.0 / 60)
        } else {
            schedule(interval: sensor != nil ? 1.0 / 10 : 1.0 / 2)
        }
    }

    private func render() {
        overlay.apply(fold: follower.value, style: settings.style, radiusScale: settings.intensity.radiusScale,
                      depth: settings.depth)
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
        target = latch.strength(forAngle: angle, curve: curve)
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
            follower.jump(to: max(follower.value, 1))
            target = 0
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
