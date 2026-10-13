import SwiftUI
import AppKit

public extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}

public extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }

    /// Couleur qui suit l'apparence claire / sombre.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }
}

/// Direction commune des apps vialet.app : papier chaud, encre profonde,
/// une couleur d'accent par app (`Brand.accent`).
public enum Theme {
    public static let paper = Color(light: 0xF7F3EC, dark: 0x14161B)
    public static let sidebar = Color(light: 0xEEE7DB, dark: 0x1A1D23)
    public static let card = Color(light: 0xFFFDF9, dark: 0x21252D)
    public static let ink = Color(light: 0x1E2227, dark: 0xEDE9E2)
    public static let inkSoft = Color(light: 0x6A6E75, dark: 0x9CA2AA)
    public static let inkFaint = Color(light: 0xAFB2B7, dark: 0x5B616A)
    public static let line = Color(light: 0xE3DACB, dark: 0x2D313A)

    public static let sea = Color(hex: 0x2F6FEB)
    public static let sun = Color(hex: 0xF0A020)
    public static let coral = Color(hex: 0xEC6A5C)
    public static let pine = Color(hex: 0x2E9D6E)
    public static let lavender = Color(hex: 0x8B78E6)
    public static let stone = Color(hex: 0x8A8F98)
    public static let danger = Color(hex: 0xE5484D)

    /// Titres : serif editorial (New York).
    public static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
