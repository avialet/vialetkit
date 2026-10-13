import AppKit
import Foundation
@testable import VialetKit

/// A lancer avant `paletteTests` : `Theme.configure` enregistre les polices.
let fontsTests: (String, [Test]) = ("Fonts", [
    Test("embeddedDataIsTrueType") {
        for (name, base64) in [("extraBold", Fonts.bricolageExtraBoldBase64),
                               ("semiBold", Fonts.bricolageSemiBoldBase64)] {
            guard let data = Data(base64Encoded: base64) else {
                expect(false, "\(name) : base64 illisible"); continue
            }
            expect(data.count > 50_000, "\(name) : \(data.count) octets")
            expectEqual(Array(data.prefix(4)), [0x00, 0x01, 0x00, 0x00], name)
        }
    },
    Test("registerWritesCacheFileAndRegisters") {
        MainActor.assumeIsolated {
            let faces = [(Fonts.extraBoldName, Fonts.bricolageExtraBoldBase64),
                         (Fonts.semiBoldName, Fonts.bricolageSemiBoldBase64)]
            let installed = faces.filter { NSFont(name: $0.0, size: 12) != nil }.map(\.0)
            if !installed.isEmpty {
                // La police du systeme repond deja : le chemin d'embarquement ne serait pas exerce.
                print("SKIP Fonts.registerWritesCacheFileAndRegisters : deja installee sur ce Mac : \(installed)")
                return
            }
            expect(!Fonts.registered, "registered doit etre faux avant register()")
            Fonts.register()
            expect(Fonts.registered, "registered apres register()")
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            let dir = caches.appendingPathComponent(Bundle.main.bundleIdentifier ?? "VialetKit")
                .appendingPathComponent("VialetKit/Fonts")
            for (name, base64) in faces {
                let count = Data(base64Encoded: base64)?.count ?? 0
                let path = dir.appendingPathComponent("\(name)-\(count).ttf").path
                let size = (try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber
                expectEqual(size?.intValue, count, "fichier \(path)")
                expect(NSFont(name: name, size: 12) != nil, "NSFont(name: \(name))")
            }
            Fonts.register() // deuxieme appel : sans effet
            expect(Fonts.registered)
        }
    },
    Test("displayFaceFollowsWeight") {
        expectEqual(Theme.displayFaceName(for: .bold), "BricolageGrotesque96pt-ExtraBold")
        expectEqual(Theme.displayFaceName(for: .heavy), "BricolageGrotesque96pt-ExtraBold")
        expectEqual(Theme.displayFaceName(for: .black), "BricolageGrotesque96pt-ExtraBold")
        expectEqual(Theme.displayFaceName(for: .semibold), "BricolageGrotesque-SemiBold")
        expectEqual(Theme.displayFaceName(for: .medium), "BricolageGrotesque-SemiBold")
        expectEqual(Theme.displayFaceName(for: .regular), "BricolageGrotesque-SemiBold")
    },
])
