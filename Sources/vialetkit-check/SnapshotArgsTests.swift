import AppKit
import Foundation
import SwiftUI
import VialetKit

private func parse(_ args: [String]) -> SnapshotRequest? {
    SnapshotRequest.parse(prefix: "Pince", arguments: ["/Applications/Pince.app/Contents/MacOS/Pince"] + args)
}

let snapshotArgsTests: (String, [Test]) = ("SnapshotArgs", [
    Test("absentGivesNil") {
        expect(parse([]) == nil, "sans argument")
        expect(parse(["-AllegeSnapshot", "/tmp/c"]) == nil, "autre prefixe")
        expect(parse(["-PinceSnapshot"]) == nil, "dossier manquant")
    },
    Test("directoryOnly") {
        expectEqual(parse(["-PinceSnapshot", "/tmp/c"]),
                    SnapshotRequest(directory: "/tmp/c", dark: false, only: nil, size: nil))
    },
    Test("dark") {
        expectEqual(parse(["-PinceSnapshot", "/tmp/c", "-PinceSnapshotAppearance", "dark"])?.dark, true)
        expectEqual(parse(["-PinceSnapshot", "/tmp/c", "-PinceSnapshotAppearance", "light"])?.dark, false)
    },
    Test("only") {
        expectEqual(parse(["-PinceSnapshot", "/tmp/c", "-PinceSnapshotOnly", "a,b"])?.only, ["a", "b"])
        expectEqual(parse(["-PinceSnapshot", "/tmp/c", "-PinceSnapshotOnly", " a , ,b "])?.only, ["a", "b"])
    },
    Test("size") {
        expectEqual(parse(["-PinceSnapshot", "/tmp/c", "-PinceSnapshotSize", "1000x720"])?.size,
                    CGSize(width: 1000, height: 720))
        // Taille invalide : seule la taille est ignoree.
        for bad in ["1000", "0x720", "axb", "1000x720x3"] {
            let r = parse(["-PinceSnapshot", "/tmp/c", "-PinceSnapshotSize", bad, "-PinceSnapshotAppearance", "dark"])
            expectEqual(r, SnapshotRequest(directory: "/tmp/c", dark: true, only: nil, size: nil), bad)
        }
    },
    Test("fileNames") {
        let light = SnapshotRequest(directory: "/tmp/c", dark: false, only: nil, size: nil)
        let dark = SnapshotRequest(directory: "/tmp/c", dark: true, only: ["settings"], size: nil)
        expectEqual(light.fileURL(for: "settings").path, "/tmp/c/settings.png")
        expectEqual(dark.fileURL(for: "settings").path, "/tmp/c/settings-sombre.png")
        expect(light.includes("about") && dark.includes("settings") && !dark.includes("about"), "filtre only")
    },
    Test("planFiltersAndAppOverridesStandard") {
        let standard = ["mainWindow", "settings", "about", "floatingPanel"].map { name in
            SnapshotScenario(name) { nil }
        }
        let request = SnapshotRequest(directory: "/tmp/c", dark: false, only: nil, size: nil)
        // Un scenario de l'app du meme nom remplace le standard, a sa place ; les autres s'ajoutent.
        let app = [SnapshotScenario("floatingPanel") { nil }, SnapshotScenario("detail") { nil }]
        let plan = SnapshotRunner.plan(standard + app, for: request)
        expectEqual(plan.map(\.name), ["mainWindow", "settings", "about", "floatingPanel", "detail"])
        let only = SnapshotRequest(directory: "/tmp/c", dark: false, only: ["detail", "about"], size: nil)
        expectEqual(SnapshotRunner.plan(standard + app, for: only).map(\.name), ["about", "detail"])
    },
    Test("windowSnapshotPaintsWindowBackground") {
        // Le panneau A propos laisse son fond au serveur de fenetres : le PNG le recoit sous le contenu.
        try MainActor.assumeIsolated {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vialetkit-check-\(UInt32.random(in: 0...UInt32.max)).png")
            defer { try? FileManager.default.removeItem(at: url) }
            for (background, alpha) in [(NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGFloat(1)), (.clear, 0)] {
                let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 30), styleMask: [.borderless],
                                      backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.backgroundColor = background
                window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 30))
                try WindowSnapshot.write(window, to: url)
                let pixel = NSBitmapImageRep(data: try Data(contentsOf: url))?.colorAt(x: 5, y: 5)
                expectEqual(pixel?.alphaComponent ?? -1, alpha, "\(background)")
                if alpha == 1 { expect((pixel?.redComponent ?? 0) > 0.9, "fond rouge : \(String(describing: pixel))") }
            }
        }
    },
    Test("windowSnapshotShadowFallsDown") {
        // Ombre SwiftUI y +20 : a l'ecran elle descend ; la capture doit la rendre sous la carte, contenu a l'endroit.
        try MainActor.assumeIsolated {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("vialetkit-check-\(UInt32.random(in: 0...UInt32.max)).png")
            defer { try? FileManager.default.removeItem(at: url) }
            let card = VStack(spacing: 0) {
                Rectangle().fill(Color(red: 0, green: 1, blue: 0)).frame(width: 60, height: 10)
                Rectangle().fill(Color(red: 1, green: 0, blue: 0)).frame(width: 60, height: 10)
            }
            .shadow(color: .black, radius: 2, x: 0, y: 20)
            .frame(width: 120, height: 120)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 120), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.backgroundColor = .clear
            window.contentView = NSHostingView(rootView: card)
            window.contentView?.layoutSubtreeIfNeeded()
            try WindowSnapshot.write(window, to: url)
            guard let rep = NSBitmapImageRep(data: try Data(contentsOf: url)) else {
                expect(false, "PNG illisible"); return
            }
            // Carte de y 50 a 70 (points, haut = 0) ; ombre attendue de 70 a 90, rien au-dessus.
            let scale = rep.pixelsWide / 120
            func pixel(_ y: Int) -> NSColor? { rep.colorAt(x: 60 * scale, y: y * scale) }
            let above = pixel(40)?.alphaComponent ?? -1
            let below = pixel(80)?.alphaComponent ?? -1
            expect(below > 0.5 && above < 0.1, "ombre sous la carte : dessus \(above), dessous \(below)")
            expect((pixel(55)?.greenComponent ?? 0) > 0.8 && (pixel(65)?.redComponent ?? 0) > 0.8,
                   "contenu a l'endroit (vert en haut, rouge en bas)")
        }
    },
    Test("notRequestedDoesNothing") {
        MainActor.assumeIsolated {
            expect(!SnapshotRunner.runIfRequested(prefix: "VialetKitCheckAbsent", scenarios: []), "rien demande")
        }
    },
])
