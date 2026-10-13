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
/// une palette d'accent par app, posee au lancement par `Theme.configure(_:)`.
public enum Theme {
    // MARK: Palette d'accent

    /// Palette de l'app ; `.sea` tant que `configure` n'a pas ete appele.
    @MainActor public static private(set) var palette: AccentPalette = .sea

    /// A appeler une fois au lancement (init de l'App), avant le premier rendu.
    /// Enregistre aussi Bricolage Grotesque pour `display` (repli SF Rounded en cas d'echec).
    @MainActor public static func configure(_ palette: AccentPalette) {
        self.palette = palette
        Fonts.register()
    }

    @MainActor public static var accent: Color { palette.color }
    @MainActor public static var accentBackground: Color { palette.backgroundColor }
    @MainActor public static var accentDeep: Color { palette.deepColor }
    @MainActor public static var accentPale: Color { palette.paleColor }
    @MainActor public static var accentNight: Color { palette.nightColor }
    @MainActor public static var accentNightInk: Color { palette.nightInkColor }
    /// Fond de selection (lignes, champs actifs) : accent a 14 %.
    @MainActor public static var accentSelection: Color { palette.color.opacity(0.14) }
    /// Bouton principal, comme sur les sites : fond deep et texte blanc en clair,
    /// fond background et texte deep en sombre.
    @MainActor public static var accentPrimaryButtonBackground: Color {
        Color(light: palette.deep, dark: palette.background)
    }
    @MainActor public static var accentPrimaryButtonForeground: Color {
        Color(light: 0xFFFFFF, dark: palette.deep)
    }

    /// Papier de `AmbientBackground` : `paper` en clair ; en sombre, `paper` melange
    /// a `night` a 35 %.
    @MainActor public static var ambientPaper: Color {
        Color(light: paperLight, dark: AccentPalette.mix(paperDark, palette.night, fraction: 0.35))
    }

    // MARK: Jetons

    /// Rayons des coins (style `.continuous`).
    public enum Radius {
        public static let key: CGFloat = 4
        public static let icon: CGFloat = 7
        public static let chip: CGFloat = 8
        public static let row: CGFloat = 10
        public static let item: CGFloat = 12
        public static let card: CGFloat = 16
        public static let editor: CGFloat = 18
        public static let panel: CGFloat = 22
    }

    /// Espacements.
    public enum Space {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 26
    }

    public struct ShadowToken: Sendable {
        public let color: Color
        public let radius: CGFloat
        public let y: CGFloat
    }

    /// Ombres : `.shadow(color: s.color, radius: s.radius, y: s.y)`.
    public enum Shadow {
        public static let panel = ShadowToken(color: Color.black.opacity(0.22), radius: 18, y: 8)
    }

    // MARK: Couleurs fixes

    static let paperLight: UInt32 = 0xF7F3EC
    static let paperDark: UInt32 = 0x14161B
    public static let paper = Color(light: paperLight, dark: paperDark)
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

    // MARK: Typographie

    /// Titres : Bricolage Grotesque embarquee (ExtraBold pour `.bold` et plus gras,
    /// SemiBold sinon), comme les sites ; SF Rounded `.heavy` si la police n'est pas
    /// enregistree (`configure` pas encore appele, ou echec). Le texte courant reste en `ui`.
    @MainActor public static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        guard Fonts.registered else { return .system(size: size, weight: .heavy, design: .rounded) }
        return .custom(displayFaceName(for: weight), size: size)
    }

    /// Face de `display` : ExtraBold pour `.bold`, `.heavy`, `.black`, SemiBold sinon.
    static func displayFaceName(for weight: Font.Weight) -> String {
        weight == .bold || weight == .heavy || weight == .black ? Fonts.extraBoldName : Fonts.semiBoldName
    }

    /// Ancien `display` (serif editorial, New York), garde pour la transition de Pico.
    public static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    public static func ui(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
