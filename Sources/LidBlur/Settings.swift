import Foundation

enum BlurStyle: String, CaseIterable {
    case unfold
    case uniform

    var title: String {
        switch self {
        case .unfold: return "Unfold (clears from the bottom)"
        case .uniform: return "Uniform"
        }
    }
}

enum Intensity: String, CaseIterable {
    case subtle
    case normal
    case strong

    var title: String { rawValue.capitalized }

    var maxOpacity: Double {
        switch self {
        case .subtle: return 0.6
        case .normal: return 0.85
        case .strong: return 1.0
        }
    }
}

final class Settings {
    static let shared = Settings()

    static let clearAngleChoices: [Double] = [20, 40, 60]

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

    /// Lid angle (degrees) that triggers the clear animation when opening.
    var clearAngle: Double {
        get { defaults.object(forKey: "openTriggerAngle") as? Double ?? 40 }
        set { defaults.set(newValue, forKey: "openTriggerAngle") }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }
}
