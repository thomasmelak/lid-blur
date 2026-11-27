import Foundation

/// Maps a lid angle (degrees) to a fold amount between 0 (open, sharp) and 1 (closed, blurred).
public struct BlurCurve: Equatable, Sendable {
    /// At or below this angle the screen is fully blurred.
    public var closedAngle: Double
    /// At or above this angle the screen is completely sharp.
    public var clearAngle: Double

    public init(closedAngle: Double = 10, clearAngle: Double = 80) {
        self.closedAngle = closedAngle
        self.clearAngle = clearAngle
    }

    public func strength(forAngle angle: Double) -> Double {
        guard clearAngle > closedAngle else { return angle <= closedAngle ? 1 : 0 }
        let t = Easing.clamp((angle - closedAngle) / (clearAngle - closedAngle))
        return 1 - Easing.smoothstep(t)
    }
}

/// Keeps an open screen sharp against small wobbles of the lid (or sensor noise) near the clear
/// angle. Once the lid has reached the clear angle, the blur only comes back after it has closed
/// `deadband` degrees below it; it is released again as soon as the lid is back at the clear angle.
public struct OpenLatch: Equatable, Sendable {
    public var deadband: Double
    public private(set) var isOpen = false

    public init(deadband: Double = 8) {
        self.deadband = deadband
    }

    public mutating func strength(forAngle angle: Double, curve: BlurCurve) -> Double {
        if angle >= curve.clearAngle {
            isOpen = true
        } else if angle < curve.clearAngle - deadband {
            isOpen = false
        }
        return isOpen ? 0 : curve.strength(forAngle: angle)
    }
}

/// A critically damped spring that follows a moving target. It eases in and out of every
/// change, keeps its velocity when the target moves again, and never overshoots. A slow lid
/// is tracked closely; a lid flung open still glides into sharpness instead of snapping.
public struct EasedFollower: Equatable, Sendable {
    public private(set) var value: Double
    public private(set) var velocity: Double = 0
    /// Stiffness in 1/s. Settles within ~1% after about 6.6 / omega seconds.
    public var omega: Double

    public init(value: Double = 0, omega: Double = 7.5) {
        self.value = value
        self.omega = omega
    }

    public var isSettled: Bool { velocity == 0 }

    public mutating func jump(to value: Double) {
        self.value = value
        velocity = 0
    }

    /// Advances by `dt` seconds towards `target` (exact solution, stable for any step size).
    public mutating func step(towards target: Double, dt: Double) {
        guard dt > 0 else { return }
        let x0 = value - target
        let v0 = velocity
        let e = exp(-omega * dt)
        let x = (x0 + (v0 + omega * x0) * dt) * e
        let v = (v0 - omega * (v0 + omega * x0) * dt) * e
        value = target + x
        velocity = v
        if abs(x) < 0.002, abs(v) < 0.02 {
            value = target
            velocity = 0
        }
    }
}

public enum Easing {
    public static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        min(max(x, lo), hi)
    }

    public static func smoothstep(_ t: Double) -> Double {
        let t = clamp(t)
        return t * t * (3 - 2 * t)
    }

    public static func easeOutCubic(_ t: Double) -> Double {
        let t = clamp(t)
        let u = 1 - t
        return 1 - u * u * u
    }

    public static func easeInOutCubic(_ t: Double) -> Double {
        let t = clamp(t)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// Frame-rate independent exponential approach of `current` towards `target`.
    public static func approach(_ current: Double, _ target: Double, dt: Double, timeConstant: Double) -> Double {
        guard timeConstant > 0 else { return target }
        let k = 1 - exp(-dt / timeConstant)
        let next = current + (target - current) * k
        return abs(next - target) < 0.001 ? target : next
    }
}

/// How the screen looks for a given fold amount (0 = flat open, 1 = closed), tuned to the
/// foldable-phone animation: the blur comes in quickly as soon as the panel starts to fold,
/// while the screen only darkens in the second half, fading to almost black when closed.
public struct FoldLook: Equatable, Sendable {
    /// Blur coverage, 0...1.
    public let blur: Double
    /// Darkening, 0...1 (scaled by the overlay's maximum dim).
    public let dim: Double

    public init(fold: Double) {
        let f = Easing.clamp(fold)
        blur = Easing.easeOutCubic(f / 0.4)
        dim = Easing.smoothstep((f - 0.3) / 0.7)
    }
}

/// A variable blur over the whole screen. The radius itself is the gradient: strongest at
/// the top edge, weaker towards the hinge, but never zero anywhere while the screen is folded.
/// Nothing is ever revealed sharp; the whole screen eases to sharp together as the lid opens.
public struct BlurProfile: Equatable, Sendable {
    /// Blur radius at the top edge, in points.
    public let topRadius: Double
    /// Radius at the hinge as a fraction of the top radius (`hingeFloor`...1).
    public let hingeRatio: Double
    /// Darkening, 0...1.
    public let dim: Double

    /// Top radius at full strength. Strong enough to hide text, soft enough that windows,
    /// icons and the wallpaper stay recognisable, like the foldable-phone panel.
    public static let maxRadius = 30.0
    /// The hinge never gets less than this share of the top radius.
    public static let hingeFloor = 0.4
    /// Below this radius the effect is invisible and the overlay can be removed.
    public static let visibleRadius = 0.25

    /// - Parameters:
    ///   - fold: 0 with the lid open, 1 with it closed.
    ///   - gradient: false for an even blur over the whole screen.
    ///   - scale: intensity multiplier for the radius.
    public init(fold: Double, gradient: Bool = true, scale: Double = 1) {
        let f = Easing.clamp(fold)
        let look = FoldLook(fold: f)
        topRadius = BlurProfile.maxRadius * Easing.clamp(scale) * look.blur
        // Closed, the panel is evenly blurred; as it opens the hinge clears faster than the
        // top, but stays above the floor until the whole screen is sharp.
        hingeRatio = gradient ? BlurProfile.hingeFloor + (1 - BlurProfile.hingeFloor) * Easing.smoothstep(f) : 1
        dim = look.dim
    }

    public var hingeRadius: Double { topRadius * hingeRatio }
    public var isVisible: Bool { topRadius >= BlurProfile.visibleRadius || dim > 0.002 }

    /// Share of the top radius at a height measured from the top edge (0) to the hinge (1).
    public static func coverage(atDepth depth: Double, hingeRatio: Double) -> Double {
        1 - (1 - Easing.clamp(hingeRatio)) * Easing.smoothstep(depth)
    }
}

/// How far the picture sits "behind" the glass for a given fold amount. Closed, the picture
/// is smaller and tilted back from the hinge, as if it were deeper than the display; as the lid
/// opens it rises forward and upright until it fills the screen.
public struct DepthLook: Equatable, Sendable {
    /// Uniform scale of the picture, `minScale`...1.
    public let scale: Double
    /// Backward tilt around the hinge, in degrees (0 = upright).
    public let tilt: Double

    public static let minScale = 0.86
    public static let maxTilt = 14.0

    public init(fold: Double) {
        // Eased on both ends: the picture leaves the glass gently, travels, and settles softly.
        let d = Easing.easeInOutCubic(Easing.clamp(fold))
        scale = 1 - (1 - DepthLook.minScale) * d
        tilt = DepthLook.maxTilt * d
    }

    public var isFlat: Bool { scale >= 0.9995 && tilt <= 0.01 }
}
