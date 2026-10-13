import AppKit
import Foundation
import SwiftUI
import VialetKit

/// Palettes reelles des apps (Brand.swift), calculees par scripts/teintes.py.
private let realPalettes: [(String, AccentPalette)] = [
    ("Pico", AccentPalette(accent: 0xF0A020, background: 0xF0A020, deep: 0x5F3D09,
                           pale: 0xFFEFDC, night: 0x271701, nightInk: 0xF1D2AD)),
    ("Allege", AccentPalette(accent: 0x2E9D6E, background: 0x2E9D6E, deep: 0x012B1A,
                             pale: 0xE1F8EB, night: 0x032114, nightInk: 0xB6E4CB)),
    ("Pince", .sea),
    ("Brouillon", AccentPalette(accent: 0x8B78E6, background: 0x8B78E6, deep: 0x261455,
                                pale: 0xF1F0FF, night: 0x1A172E, nightInk: 0xD5D2FD)),
]

let paletteTests: (String, [Test]) = ("Palette", [
    Test("contrastBlackOnWhiteIs21") {
        expect(abs(AccentPalette.contrast(0xFFFFFF, 0x000000) - 21) < 0.01)
        expect(abs(AccentPalette.contrast(0x000000, 0xFFFFFF) - 21) < 0.01, "symetrique")
        expect(abs(AccentPalette.contrast(0x2F6FEB, 0x2F6FEB) - 1) < 0.0001, "meme couleur")
    },
    Test("seaIsKitDefault") {
        let sea = AccentPalette.sea
        expectEqual(sea, AccentPalette(accent: 0x2F6FEB, background: 0x2F6FEB, deep: 0x00001F,
                                       pale: 0xEBF2FF, night: 0x0F1A2F, nightInk: 0xC4D8FD))
    },
    Test("realPalettesReachAA") {
        for (name, p) in realPalettes {
            let a = AccentPalette.contrast(p.deep, p.background)
            let b = AccentPalette.contrast(p.deep, p.pale)
            let c = AccentPalette.contrast(p.nightInk, p.night)
            expect(a >= 4.5, "\(name) deep/background \(a)")
            expect(b >= 4.5, "\(name) deep/pale \(b)")
            expect(c >= 4.5, "\(name) nightInk/night \(c)")
        }
    },
    Test("configureSetsPalette") {
        MainActor.assumeIsolated {
            for (name, p) in realPalettes {
                Theme.configure(p)
                expectEqual(Theme.palette, p, name)
            }
            Theme.configure(.sea)
            expectEqual(Theme.palette, .sea)
        }
    },
    Test("tokensKeepCurrentValues") {
        expectEqual([Theme.Radius.key, Theme.Radius.icon, Theme.Radius.chip, Theme.Radius.row,
                     Theme.Radius.item, Theme.Radius.card, Theme.Radius.editor, Theme.Radius.panel],
                    [4, 7, 8, 10, 12, 16, 18, 22], "Radius")
        expectEqual([Theme.Space.xs, Theme.Space.s, Theme.Space.m, Theme.Space.l, Theme.Space.xl, Theme.Space.xxl],
                    [4, 8, 12, 16, 20, 26], "Space")
        expectEqual(Theme.Shadow.panel.radius, 18)
        expectEqual(Theme.Shadow.panel.y, 8)
        expectEqual(NSColor(Theme.Shadow.panel.color).alphaComponent, 0.22, "ombre")
    },
    Test("primaryButtonFollowsAppearance") {
        MainActor.assumeIsolated {
            let p = realPalettes[3].1 // Brouillon : accent different de deep et de blanc
            Theme.configure(p)
            let bg = Theme.accentPrimaryButtonBackground, fg = Theme.accentPrimaryButtonForeground
            expectEqual(hex(bg, dark: false), p.deep, "fond clair")
            expectEqual(hex(fg, dark: false), 0xFFFFFF, "texte clair")
            expectEqual(hex(bg, dark: true), p.background, "fond sombre")
            expectEqual(hex(fg, dark: true), p.deep, "texte sombre")
            Theme.configure(.sea)
        }
    },
    Test("accentSelectionIsAccentAt14Percent") {
        MainActor.assumeIsolated {
            let c = NSColor(Theme.accentSelection).usingColorSpace(.sRGB)
            expect(abs((c?.alphaComponent ?? 0) - 0.14) < 0.001, "alpha \(String(describing: c?.alphaComponent))")
            expectEqual(c.map { rgb($0) }, Theme.palette.accent, "teinte")
        }
    },
])

let paletteMixTests: (String, [Test]) = ("PaletteMix", [
    Test("mixBlendsPerChannel") {
        expectEqual(AccentPalette.mix(0x000000, 0xFFFFFF, fraction: 0), 0x000000)
        expectEqual(AccentPalette.mix(0x000000, 0xFFFFFF, fraction: 1), 0xFFFFFF)
        expectEqual(AccentPalette.mix(0x14161B, 0x0F1A2F, fraction: 0.35), 0x121722)
    },
])

/// Hex sRGB d'une couleur resolue dans l'apparence claire ou sombre (alpha ignore).
private func hex(_ color: Color, dark: Bool) -> UInt32 {
    var out: UInt32 = 0
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        out = NSColor(color).usingColorSpace(.sRGB).map { rgb($0) } ?? 0xDEAD
    }
    return out
}

private func rgb(_ c: NSColor) -> UInt32 {
    func byte(_ v: CGFloat) -> UInt32 { UInt32((min(max(v, 0), 1) * 255).rounded()) }
    return byte(c.redComponent) << 16 | byte(c.greenComponent) << 8 | byte(c.blueComponent)
}
