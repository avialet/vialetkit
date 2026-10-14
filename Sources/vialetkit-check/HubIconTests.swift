import AppKit
@testable import VialetKit

/// Pixel (x, y depuis le haut) d'une image rendue a `pixels` de cote : (r, g, b, a) 0-255.
private func pixel(_ image: NSImage, pixels: Int, x: Int, y: Int) -> (Int, Int, Int, Int) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
    return (Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
            Int((c.blueComponent * 255).rounded()), Int((c.alphaComponent * 255).rounded()))
}

let iconTests: (String, [Test]) = ("Icons", [
    Test("statusIconIsTemplateAtMenuBarSize") {
        MainActor.assumeIsolated {
            for variant in HubStatusIcon.Variant.allCases {
                let image = HubStatusIcon.image(variant)
                expect(image.isTemplate, "\(variant) en image template")
                expectEqual(image.size, NSSize(width: 18, height: 18))
                expect(pixel(image, pixels: 36, x: 18, y: 18).3 > 0 || variant != .tons, "\(variant) : centre (jour ou trou ailleurs)")
                expect(pixel(image, pixels: 36, x: 10, y: 26).3 > 0, "\(variant) : quart bas gauche dessine")
                expectEqual(pixel(image, pixels: 36, x: 0, y: 0).3, 0, "\(variant) : coin transparent")
            }
        }
    },
    Test("chosenVariantIsTons") {
        expectEqual(HubStatusIcon.Variant.chosen, .tons)
    },
    Test("notchClearsRoomForTheDot") {
        MainActor.assumeIsolated {
            let plain = HubStatusIcon.image(.tons, notched: false)
            let notched = HubStatusIcon.image(.tons, notched: true)
            // Le point est en haut a droite : (30, 6) sur 36 px (y depuis le haut).
            expect(pixel(plain, pixels: 36, x: 30, y: 6).3 > 0, "sans encoche : plein")
            expectEqual(pixel(notched, pixels: 36, x: 30, y: 6).3, 0, "avec encoche : vide")
            expect(pixel(notched, pixels: 36, x: 8, y: 28).3 > 0, "le reste demeure")
        }
    },
    Test("tonesAlternateAroundThePlate") {
        let a = HubStatusIcon.tones
        expectEqual(a.count, 5)
        for i in 0..<a.count {
            let next = a[(i + 1) % a.count]
            expect(abs(a[i] - next) >= 0.25, "secteurs voisins distincts : \(a[i]) / \(next)")
        }
        expect(a.min()! >= 0.3, "aucun secteur presque invisible")
    },
    Test("hubPlateDrawsOneSectorPerPaletteFromNoon") {
        let red = AccentPalette(accent: 0xFF0000, background: 0xFF0000, deep: 0, pale: 0, night: 0, nightInk: 0)
        let blue = AccentPalette(accent: 0x0000FF, background: 0x0000FF, deep: 0, pale: 0, night: 0, nightInk: 0)
        let image = HubPlate.image([red, blue], pixels: 40)
        // Deux secteurs depuis midi, sens horaire : rouge a droite, bleu a gauche.
        let right = pixel(image, pixels: 40, x: 30, y: 20), left = pixel(image, pixels: 40, x: 10, y: 20)
        expect(right.0 > 200 && right.2 < 50, "droite rouge : \(right)")
        expect(left.2 > 200 && left.0 < 50, "gauche bleue : \(left)")
        expectEqual(pixel(image, pixels: 40, x: 0, y: 0).3, 0, "coin arrondi transparent")
    },
    Test("hubPlateWithoutPalettesIsNeutral") {
        let image = HubPlate.image([], pixels: 20)
        expect(pixel(image, pixels: 20, x: 10, y: 10).3 > 0)
    },
])
