import AppKit

/// Apparence choisie par l'utilisateur (Presentation > Apparence).
public enum AppearanceChoice: String, CaseIterable, Sendable {
    case system, light, dark

    public var label: String {
        switch self {
        case .system: "Comme le système"
        case .light: "Clair"
        case .dark: "Sombre"
        }
    }

    public static func current(defaultsKey: String) -> AppearanceChoice {
        AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    @MainActor
    public func apply(defaultsKey: String) {
        UserDefaults.standard.set(rawValue, forKey: defaultsKey)
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}
