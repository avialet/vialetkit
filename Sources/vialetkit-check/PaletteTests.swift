import Foundation
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
        expectEqual(Theme.Radius.icon, 7)
        expectEqual(Theme.Radius.row, 10)
        expectEqual(Theme.Radius.item, 12)
        expectEqual(Theme.Radius.card, 16)
        expectEqual(Theme.Space.l, 16)
        expectEqual(Theme.Shadow.panel.radius, 18)
    },
])
