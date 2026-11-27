import Foundation

enum BlurStyle: String, CaseIterable {
    case unfold
    case uniform

    var title: String {
        switch self {
        case .unfold: return "Gradient (softer at the hinge)"
        case .uniform: return "Uniform"
        }
    }
}

enum Intensity: String, CaseIterable {
    case subtle
    case normal
    case strong

    var title: String { rawValue.capitalized }

    /// Multiplier for the blur radius.
    var radiusScale: Double {
        switch self {
        case .subtle: return 0.55
        case .normal: return 0.8
        case .strong: return 1.0
        }
    }
}

final class Settings {
    static let shared = Settings()

    static let clearAngleRange: ClosedRange<Double> = 30...130

    private let defaults = UserDefaults.standard

    var enabled: Bool {
        get { defaults.object(forKey: "enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "enabled") }
    }

    var style: BlurStyle {
        get { defaults.string(forKey: "style").flatMap(BlurStyle.init(rawValue:)) ?? .unfold }
        set { defaults.set(newValue.rawValue, forKey: "style") }
    }

    var intensity: Intensity {
        get { defaults.string(forKey: "intensity").flatMap(Intensity.init(rawValue:)) ?? .normal }
        set { defaults.set(newValue.rawValue, forKey: "intensity") }
    }

    /// Lid angle (degrees) at which the screen becomes completely sharp.
    var clearAngle: Double {
        get { defaults.object(forKey: "clearAngle") as? Double ?? 80 }
        set { defaults.set(newValue, forKey: "clearAngle") }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }
}
