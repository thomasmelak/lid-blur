import Foundation

/// Turns the lid angle into open/closed events. The angle only triggers the animation; the
/// animation itself runs on its own easing curve, so opening the lid quickly still eases into
/// sharpness. A little hysteresis stops the state flickering when the lid rests near the edge.
public struct LidTrigger: Equatable, Sendable {
    /// The lid counts as open once it rises to this angle.
    public var openAngle: Double
    /// The lid counts as closed again once it falls this many degrees below `openAngle`.
    public var hysteresis: Double
    public private(set) var isOpen: Bool?

    public init(openAngle: Double = 40, hysteresis: Double = 10) {
        self.openAngle = openAngle
        self.hysteresis = hysteresis
    }

    /// Feeds a new angle reading. Returns the new state when it changed, else nil.
    public mutating func update(angle: Double) -> Bool? {
        let open: Bool
        if isOpen == true {
            open = angle > openAngle - hysteresis
        } else {
            open = angle >= openAngle
        }
        let changed = open != isOpen
        isOpen = open
        return changed ? open : nil
    }

    public mutating func reset() {
        isOpen = nil
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

/// Describes the "unfold" reveal: the sharp area rises from the bottom edge of the screen
/// (the hinge) towards the top as the blur strength falls. Positions are fractions of the
/// screen height measured from the bottom.
public struct UnfoldMask: Equatable, Sendable {
    /// Height fraction (0...1), from the bottom, that is completely sharp.
    public let clearEdge: Double
    /// Height fraction where the blur is back to full strength.
    public let blurEdge: Double
    /// Blur coverage at the very bottom edge (0 = sharp, 1 = blurred).
    public let bottomCoverage: Double

    public static let feather = 0.35

    public init(strength: Double) {
        let progress = 1 - Easing.clamp(strength)
        let inner = progress * (1 + UnfoldMask.feather) - UnfoldMask.feather
        let outer = inner + UnfoldMask.feather
        clearEdge = Easing.clamp(inner)
        blurEdge = Easing.clamp(outer)
        bottomCoverage = inner >= 0 ? 0 : Easing.clamp(-inner / UnfoldMask.feather)
    }

    public var isFullyBlurred: Bool { blurEdge <= 0 }
    public var isFullyClear: Bool { clearEdge >= 1 }
}
