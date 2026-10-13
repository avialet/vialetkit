import SwiftUI
import AppKit

/// Teintes d'une app, calculees par scripts/teintes.py du depot vialetapps
/// (memes valeurs que l'affiche, les sites et la plaque d'icone).
/// - `accent` : la couleur de l'app (controles, halos, selection) ;
/// - `background` / `deep` : fond et texte de l'affiche ;
/// - `pale` : fond clair teinte ; `night` / `nightInk` : fond et texte en sombre.
public struct AccentPalette: Sendable, Equatable {
    public let accent, background, deep, pale, night, nightInk: UInt32

    public init(accent: UInt32, background: UInt32, deep: UInt32, pale: UInt32, night: UInt32, nightInk: UInt32) {
        self.accent = accent; self.background = background; self.deep = deep
        self.pale = pale; self.night = night; self.nightInk = nightInk
    }

    public var color: Color { Color(hex: accent) }
    public var backgroundColor: Color { Color(hex: background) }
    public var deepColor: Color { Color(hex: deep) }
    public var paleColor: Color { Color(hex: pale) }
    public var nightColor: Color { Color(hex: night) }
    public var nightInkColor: Color { Color(hex: nightInk) }

    /// Contraste WCAG (1...21) entre deux couleurs hex.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Luminance relative WCAG 2.x d'une couleur sRGB.
    static func luminance(_ hex: UInt32) -> Double {
        func channel(_ shift: UInt32) -> Double {
            let c = Double((hex >> shift) & 0xFF) / 255
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(16) + 0.7152 * channel(8) + 0.0722 * channel(0)
    }

    /// Melange `fraction` (0...1) de `other` dans `base`, canal par canal en sRGB.
    public static func mix(_ base: UInt32, _ other: UInt32, fraction: Double) -> UInt32 {
        let f = min(max(fraction, 0), 1)
        var out: UInt32 = 0
        for shift in [UInt32(16), 8, 0] {
            let x = Double((base >> shift) & 0xFF), y = Double((other >> shift) & 0xFF)
            out |= UInt32((x + (y - x) * f).rounded()) << shift
        }
        return out
    }

    /// Defaut du kit (Pince) : bleu mer.
    public static let sea = AccentPalette(accent: 0x2F6FEB, background: 0x2F6FEB, deep: 0x00001F,
                                          pale: 0xEBF2FF, night: 0x0F1A2F, nightInk: 0xC4D8FD)
}
