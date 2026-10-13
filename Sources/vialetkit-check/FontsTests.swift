import AppKit
import Foundation
@testable import VialetKit

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
    Test("registerMakesFontsAvailable") {
        MainActor.assumeIsolated {
            Fonts.register()
            expect(Fonts.registered)
            expect(NSFont(name: "BricolageGrotesque96pt-ExtraBold", size: 12) != nil, "ExtraBold")
            expect(NSFont(name: "BricolageGrotesque-SemiBold", size: 12) != nil, "SemiBold")
            Fonts.register() // deuxieme appel : deja enregistree, sans effet
            expect(Fonts.registered)
        }
    },
])
