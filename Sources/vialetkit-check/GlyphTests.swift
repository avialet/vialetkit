import AppKit
import Foundation
import VialetKit

/// Glyphes reels des apps (Brand.swift de Pico, Allege, Pince, Brouillon).
private let realGlyphs: [(String, String)] = [
    ("Pico", "M 22 54 L 44 76 L 80 28"),
    ("Allege", "M 50 16 L 50 60 M 32 42 L 50 60 L 68 42 M 24 82 L 76 82"),
    ("Pince", "M 20 18 L 40 50 L 20 82 M 80 18 L 60 50 L 80 82"),
    ("Brouillon", "M 18 70 C 28 34 40 34 50 54 C 60 74 72 74 82 40"),
]

private let unit = CGRect(x: 0, y: 0, width: 100, height: 100)

let glyphTests: (String, [Test]) = ("Glyph", [
    Test("realGlyphsParseInsideTheBox") {
        for (name, d) in realGlyphs {
            do {
                let box = try GlyphPath.cgPath(d, in: unit).boundingBoxOfPath
                expect(box.width > 0 && box.height > 0, "\(name) boite vide")
                expect(box.minX >= 0 && box.minY >= 0 && box.maxX <= 100 && box.maxY <= 100, "\(name) \(box)")
            } catch {
                expect(false, "\(name) : \(error)")
            }
        }
    },
    Test("lineGivesExpectedBox") {
        let box = try GlyphPath.cgPath("M 10 10 L 90 90", in: unit).boundingBoxOfPath
        expect(abs(box.minX - 10) < 0.01 && abs(box.minY - 10) < 0.01, "\(box)")
        expect(abs(box.maxX - 90) < 0.01 && abs(box.maxY - 90) < 0.01, "\(box)")
    },
    Test("pathIsFlippedAndScaledIntoRect") {
        // y vers le bas dans le glyphe, vers le haut dans AppKit : (10, 20) -> (2 + 10/2, 4 + (100-20)/2).
        let box = try GlyphPath.cgPath("M 10 20 H 10", in: CGRect(x: 2, y: 4, width: 50, height: 50)).boundingBoxOfPath
        expect(abs(box.minX - 7) < 0.01 && abs(box.minY - 44) < 0.01, "\(box)")
    },
    Test("errors") {
        expectThrowsGlyph(.empty) { _ = try GlyphPath.cgPath("", in: unit) }
        expectThrowsGlyph(.command("A")) { _ = try GlyphPath.cgPath("M 0 0 A 1 1", in: unit) }
        expectThrowsGlyph(.arguments("M")) { _ = try GlyphPath.cgPath("M 10", in: unit) }
    },
    Test("templateImage") {
        let image = GlyphImage.template(realGlyphs[0].1, pointSize: 18)
        expect(image.isTemplate, "isTemplate")
        expectEqual(image.size, NSSize(width: 18, height: 18))
        expect(image.cgImage(forProposedRect: nil, context: nil, hints: nil) != nil, "rendu")
        let invalid = GlyphImage.template("M 0 0 A 1 1", pointSize: 22)
        expectEqual(invalid.size, NSSize(width: 22, height: 22), "glyphe invalide : image vide")
    },
    Test("plateImage") {
        for inverse in [false, true] {
            let image = GlyphImage.plate(.sea, glyph: realGlyphs[1].1, pixels: 64, inverse: inverse)
            expectEqual(image.size, NSSize(width: 64, height: 64))
            guard let rep = image.representations.first as? NSBitmapImageRep else {
                expect(false, "pas de bitmap"); continue
            }
            expectEqual(rep.pixelsWide, 64); expectEqual(rep.pixelsHigh, 64)
            expect((rep.colorAt(x: 32, y: 32)?.alphaComponent ?? 0) > 0, "centre transparent")
            expectEqual(rep.colorAt(x: 0, y: 0)?.alphaComponent ?? 1, 0, "coin arrondi transparent")
        }
        // Glyphe vide : plaque sans trait, pixel central a la couleur de l'accent.
        let bare = GlyphImage.plate(.sea, glyph: "", pixels: 64)
        let c = (bare.representations.first as? NSBitmapImageRep)?.colorAt(x: 32, y: 32)?.usingColorSpace(.sRGB)
        expect(abs((c?.blueComponent ?? 0) - CGFloat(0xEB) / 255) < 0.02, "accent \(String(describing: c))")
    },
])

private func expectThrowsGlyph(_ expected: GlyphError, _ body: () throws -> Void,
                               file: StaticString = #filePath, line: UInt = #line) {
    do {
        try body()
        expect(false, "pas d'erreur, attendu \(expected)", file: file, line: line)
    } catch let error as GlyphError {
        expectEqual(String(describing: error), String(describing: expected), file: file, line: line)
    } catch {
        expect(false, "erreur inattendue \(error)", file: file, line: line)
    }
}
