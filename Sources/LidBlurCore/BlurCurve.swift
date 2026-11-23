import Foundation

/// Maps a lid angle (degrees) to a blur strength between 0 (sharp) and 1 (fully blurred).
public struct BlurCurve: Equatable, Sendable {
    /// At or below this angle the screen is fully blurred.
    public var closedAngle: Double
    /// At or above this angle the screen is completely sharp.
    public var clearAngle: Double

    public init(closedAngle: Double = 10, clearAngle: Double = 70) {
        self.closedAngle = closedAngle
        self.clearAngle = clearAngle
    }

    public func strength(forAngle angle: Double) -> Double {
        guard clearAngle > closedAngle else { return angle <= closedAngle ? 1 : 0 }
        let t = Easing.clamp((angle - closedAngle) / (clearAngle - closedAngle))
        return 1 - Easing.smoothstep(t)
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

/// Describes the radial "unfold" reveal: the sharp area grows from the centre of the screen
/// outwards as the blur strength falls.
public struct UnfoldMask: Equatable, Sendable {
    /// Fraction of the radius (0...1) that is completely sharp.
    public let clearRadius: Double
    /// Fraction of the radius where the blur is back to full strength.
    public let blurRadius: Double
    /// Blur coverage at the very centre (0 = sharp, 1 = blurred).
    public let centreCoverage: Double

    public static let feather = 0.35

    public init(strength: Double) {
        let progress = 1 - Easing.clamp(strength)
        let inner = progress * (1 + UnfoldMask.feather) - UnfoldMask.feather
        let outer = inner + UnfoldMask.feather
        clearRadius = Easing.clamp(inner)
        blurRadius = Easing.clamp(outer)
        centreCoverage = inner >= 0 ? 0 : Easing.clamp(-inner / UnfoldMask.feather)
    }

    public var isFullyBlurred: Bool { blurRadius <= 0 }
    public var isFullyClear: Bool { clearRadius >= 1 }
}
