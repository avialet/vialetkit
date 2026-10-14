import Foundation
@testable import VialetKit

private let pico = AppIdentity(name: "Pico", displayName: "Pico", repository: "avialet/pico",
                               bundleIdentifier: "fr.vialet.pico",
                               palette: AccentPalette(accent: 0x2F6FEB, background: 0x2F6FEB, deep: 0x00001F,
                                                      pale: 0xEBF2FF, night: 0x0F1A2F, nightInk: 0xC4D8FD),
                               glyph: "M 20 50 L 80 50", strokeDeep: true)

private func url(_ s: String) -> URL { URL(string: s)! }

/// Dossier jetable, efface apres le test.
private func withDirectory(_ body: (URL) throws -> Void) rethrows {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vialetkit-check-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

let appURLTests: (String, [Test]) = ("AppURL", [
    Test("parsesActions") {
        expectEqual(AppURLCommand.parse(url("pico://new"), scheme: "pico"), .action("new"))
        expectEqual(AppURLCommand.parse(url("chuchote://dicter"), scheme: "chuchote"), .action("dicter"))
        expectEqual(AppURLCommand.parse(url("pico://new/"), scheme: "pico"), .action("new"))
        expectEqual(AppURLCommand.parse(url("PICO://New"), scheme: "pico"), .action("new"))
        expectEqual(AppURLCommand.parse(url("pico:new"), scheme: "pico"), .action("new"))
        expectEqual(AppURLCommand.parse(url("pico://nouvelle-tache"), scheme: "pico"), .action("nouvelle-tache"))
        expectEqual(AppURLCommand.parse(url("pico://new?x=1"), scheme: "pico"), .action("new"))
    },
    Test("reservedCommands") {
        expectEqual(AppURLCommand.parse(url("pico://"), scheme: "pico"), .open)
        expectEqual(AppURLCommand.parse(url("pico://open"), scheme: "pico"), .open)
        expectEqual(AppURLCommand.parse(url("pico://update"), scheme: "pico"), .checkForUpdates)
        expect(AppURLCommand.reserved.contains("open"))
        expect(AppURLCommand.reserved.contains("update"))
    },
    Test("rejectsOtherSchemesAndBadIdentifiers") {
        expectEqual(AppURLCommand.parse(url("allege://new"), scheme: "pico"), nil)
        expectEqual(AppURLCommand.parse(url("https://pico.vialet.app"), scheme: "pico"), nil)
        expectEqual(AppURLCommand.parse(url("pico://new/extra"), scheme: "pico"), nil)
        expectEqual(AppURLCommand.parse(url("pico://n%C3%A9"), scheme: "pico"), nil)
        expectEqual(AppURLCommand.parse(url("pico://a_b"), scheme: "pico"), nil)
    },
    Test("identifierRules") {
        expect(AppAction.isValidIdentifier("new"))
        expect(AppAction.isValidIdentifier("dicter"))
        expect(AppAction.isValidIdentifier("nouvelle-tache2"))
        expect(!AppAction.isValidIdentifier(""))
        expect(!AppAction.isValidIdentifier("-new"))
        expect(!AppAction.isValidIdentifier("New"))
        expect(!AppAction.isValidIdentifier("n\u{00E9}"))
        expect(!AppAction.isValidIdentifier(String(repeating: "a", count: 41)))
    },
    Test("actionURL") {
        expectEqual(AppAction.url(scheme: "pico", id: "new"), url("pico://new"))
    },
])

let appActionsTests: (String, [Test]) = ("AppActions", [
    Test("routesURLsToHandlers") {
        MainActor.assumeIsolated {
            var log: [String] = []
            let actions = AppActions(pico, open: { log.append("open") }, checkForUpdates: { log.append("update") })
            actions.register(AppAction("new", title: "Nouvelle t\u{00E2}che", symbol: "plus", shortcut: "\u{2318}N")) {
                log.append("new")
            }
            expectEqual(actions.scheme, "pico")
            expect(actions.handle(url("pico://new")))
            expect(actions.handle(url("pico://")))
            expect(actions.handle(url("pico://update")))
            // Action inconnue : l'app s'ouvre quand meme.
            expect(actions.handle(url("pico://inconnue")))
            expect(!actions.handle(url("allege://new")))
            expectEqual(log, ["new", "open", "update", "open"])
            actions.handle([url("pico://new"), url("pico://new")])
            expectEqual(log.count, 6)
        }
    },
    Test("registerKeepsOrderAndReplacesSameId") {
        MainActor.assumeIsolated {
            let actions = AppActions(pico, open: {})
            actions.register(AppAction("new", title: "A", symbol: "plus")) {}
            actions.register(AppAction("search", title: "B", symbol: "magnifyingglass")) {}
            actions.register(AppAction("new", title: "C", symbol: "plus")) {}
            expectEqual(actions.actions.map(\.id), ["new", "search"])
            expectEqual(actions.actions.first?.title, "C")
        }
    },
    Test("defaultCheckForUpdatesOpensApp") {
        MainActor.assumeIsolated {
            var opened = 0
            let actions = AppActions(pico, open: { opened += 1 })
            expect(actions.handle(url("pico://update")))
            expectEqual(opened, 1)
        }
    },
])

let hubManifestTests: (String, [Test]) = ("HubManifest", [
    Test("buildsFromIdentity") {
        let m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico",
                            actions: [AppAction("new", title: "Nouvelle t\u{00E2}che", symbol: "plus", shortcut: "\u{2318}N")])
        expectEqual(m.format, 1)
        expectEqual(m.bundleIdentifier, "fr.vialet.pico")
        expectEqual(m.name, "Pico")
        expectEqual(m.displayName, "Pico")
        expectEqual(m.repository, "avialet/pico")
        expectEqual(m.site, "https://pico.vialet.app")
        expectEqual(m.palette.accent, "#2F6FEB")
        expectEqual(m.palette.nightInk, "#C4D8FD")
        expectEqual(m.accentPalette, pico.palette)
        expect(m.strokeDeep)
    },
    Test("roundTripsAndStaysReadable") {
        let m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico",
                            actions: [AppAction("new", title: "Nouvelle t\u{00E2}che", symbol: "plus")])
        let data = try m.encoded()
        let text = String(decoding: data, as: UTF8.self)
        expect(text.contains("\"format\" : 1"), text)
        expect(text.contains("\"bundleIdentifier\" : \"fr.vialet.pico\""), text)
        expect(!text.contains("\\/"), "barres non echappees : \(text)")
        expectEqual(HubManifest.decode(data), m)
    },
    Test("toleratesUnknownFieldsAndNewerFormat") {
        let json = """
        {"format": 2, "bundleIdentifier": "fr.vialet.pico", "name": "Pico", "displayName": "Pico",
         "version": "0.3.0", "appPath": "/Applications/Pico.app", "scheme": "pico", "repository": "avialet/pico",
         "site": "https://pico.vialet.app", "glyph": "", "strokeDeep": false,
         "palette": {"accent": "#2F6FEB", "background": "#2F6FEB", "deep": "#00001F", "pale": "#EBF2FF",
                     "night": "#0F1A2F", "nightInk": "#C4D8FD"},
         "actions": [{"id": "new", "title": "Nouvelle", "symbol": "plus", "futur": true}], "futur": [1, 2]}
        """
        let m = HubManifest.decode(Data(json.utf8))
        expectEqual(m?.format, 2)
        expectEqual(m?.actions.map(\.id), ["new"])
        expectEqual(m?.actions.first?.shortcut, nil)
    },
    Test("rejectsInvalidManifests") {
        expectEqual(HubManifest.decode(Data("{}".utf8)), nil)
        expectEqual(HubManifest.decode(Data("pas du json".utf8)), nil)
        let noFormat = #"{"bundleIdentifier": "fr.vialet.pico", "name": "Pico"}"#
        expectEqual(HubManifest.decode(Data(noFormat.utf8)), nil)
    },
    Test("dropsInvalidActionsAndBadPalette") {
        let json = """
        {"format": 1, "bundleIdentifier": "fr.vialet.pico", "name": "Pico", "displayName": "Pico",
         "version": "0.3.0", "appPath": "/Applications/Pico.app", "scheme": "pico", "repository": "avialet/pico",
         "site": "https://pico.vialet.app", "glyph": "", "strokeDeep": false,
         "palette": {"accent": "bleu", "background": "#2F6FEB", "deep": "#00001F", "pale": "#EBF2FF",
                     "night": "#0F1A2F", "nightInk": "#C4D8FD"},
         "actions": [{"id": "Mauvais id", "title": "x", "symbol": "plus"}, {"id": "ok", "title": "Ok", "symbol": "plus"},
                     {"id": "update", "title": "Reserve", "symbol": "plus"}]}
        """
        let m = HubManifest.decode(Data(json.utf8))
        expectEqual(m?.actions.map(\.id), ["ok"])
        expectEqual(m?.accentPalette, nil)
    },
    Test("hexHelpers") {
        expectEqual(HubManifest.hex(0x0A0B0C), "#0A0B0C")
        expectEqual(HubManifest.parseHex("#0a0b0c"), 0x0A0B0C)
        expectEqual(HubManifest.parseHex("0A0B0C"), nil)
        expectEqual(HubManifest.parseHex("#0A0B0"), nil)
    },
    Test("publishesOnlyFromApplicationsFolders") {
        let home = URL(fileURLWithPath: "/Users/a")
        func ok(_ p: String) -> Bool { HubManifest.shouldPublish(bundleURL: URL(fileURLWithPath: p), home: home) }
        expect(ok("/Applications/Pico.app"))
        expect(ok("/Applications/Utilitaires/Pico.app"))
        expect(ok("/Users/a/Applications/Pico.app"))
        expect(!ok("/Users/a/Documents/PERSO/vialetapps/Pico/build/Pico.app"))
        expect(!ok("/Volumes/Pico/Pico.app"))
        expect(!ok("/private/var/folders/xy/T/AppTranslocation/1234/d/Pico.app"))
        expect(!ok("/Users/b/Applications/Pico.app"))
    },
    Test("fileLocation") {
        let dir = URL(fileURLWithPath: "/Users/a/Library/Application Support/Vialet/apps")
        expectEqual(HubManifest.fileURL(bundleIdentifier: "fr.vialet.pico", in: dir).lastPathComponent, "fr.vialet.pico.json")
        expect(HubManifest.directory.path.hasSuffix("Library/Application Support/Vialet/apps"), HubManifest.directory.path)
    },
    Test("writesAndLoadsDirectory") {
        try withDirectory { dir in
            let m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico", actions: [])
            try m.write(to: dir)
            try Data("abime".utf8).write(to: dir.appendingPathComponent("fr.vialet.casse.json"))
            try Data("{}".utf8).write(to: dir.appendingPathComponent("notes.txt"))
            let loaded = HubManifest.loadAll(from: dir)
            expectEqual(loaded.map(\.bundleIdentifier), ["fr.vialet.pico"])
            expectEqual(HubManifest.loadAll(from: dir.appendingPathComponent("absent")).count, 0)
        }
    },
    Test("boundsOnUntrustedManifests") {
        func manifest(actions: Int, title: String = "Ok", symbol: String = "plus", glyph: String = "") -> Data {
            let list = (0..<actions).map { #"{"id": "a\#($0)", "title": "\#(title)", "symbol": "\#(symbol)"}"# }
            return Data("""
            {"format": 1, "bundleIdentifier": "fr.vialet.pico", "name": "Pico", "displayName": "Pico",
             "version": "0.3.0", "appPath": "/Applications/Pico.app", "scheme": "pico", "repository": "avialet/pico",
             "site": "https://pico.vialet.app", "glyph": "\(glyph)", "strokeDeep": false,
             "palette": {"accent": "#2F6FEB", "background": "#2F6FEB", "deep": "#00001F", "pale": "#EBF2FF",
                         "night": "#0F1A2F", "nightInk": "#C4D8FD"},
             "actions": [\(list.joined(separator: ","))]}
            """.utf8)
        }
        expectEqual(HubManifest.decode(manifest(actions: 12))?.actions.count, 8, "au plus 8 actions")
        expectEqual(HubManifest.decode(manifest(actions: 2, title: String(repeating: "t", count: 61)))?.actions.count, 0, "titre > 60")
        expectEqual(HubManifest.decode(manifest(actions: 2, title: String(repeating: "t", count: 60)))?.actions.count, 2)
        expectEqual(HubManifest.decode(manifest(actions: 2, symbol: String(repeating: "s", count: 61)))?.actions.count, 0, "symbole > 60")
        expectEqual(HubManifest.decode(manifest(actions: 0, glyph: "M " + String(repeating: "1 ", count: 1000)))?.glyph, "", "glyphe > 2000 : retire")
        expectEqual(HubManifest.decode(manifest(actions: 0, glyph: "M 1 1 L 2 2"))?.glyph, "M 1 1 L 2 2")
        var big = manifest(actions: 0)
        big.append(Data(repeating: 0x20, count: HubManifest.maxFileSize))
        expectEqual(HubManifest.decode(big), nil, "fiche > 64 Ko")
        expectEqual(HubManifest.maxFileSize, 64 * 1024)
        expectEqual(HubManifest.maxActions, 8)
    },
    Test("loadAllSkipsOversizedFiles") {
        try withDirectory { dir in
            let m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico", actions: [])
            try m.write(to: dir)
            var big = try m.encoded()
            big.append(Data(repeating: 0x20, count: HubManifest.maxFileSize))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try big.write(to: dir.appendingPathComponent("fr.vialet.gros.json"))
            expectEqual(HubManifest.loadAll(from: dir).map(\.bundleIdentifier), ["fr.vialet.pico"])
        }
    },
    Test("symlinksLeavingApplicationsAreRejected") {
        try withDirectory { dir in
            let fm = FileManager.default
            let root = dir.appendingPathComponent("Applications"), outside = dir.appendingPathComponent("Ailleurs")
            for d in [root, outside, root.appendingPathComponent("Pico.app"), outside.appendingPathComponent("Evil.app"),
                      outside.appendingPathComponent("Dossier/Evil.app")] {
                try fm.createDirectory(at: d, withIntermediateDirectories: true)
            }
            try fm.createSymbolicLink(at: root.appendingPathComponent("Lien.app"), withDestinationURL: outside.appendingPathComponent("Evil.app"))
            try fm.createSymbolicLink(at: root.appendingPathComponent("Dossier"), withDestinationURL: outside.appendingPathComponent("Dossier"))
            try fm.createSymbolicLink(at: root.appendingPathComponent("Alias.app"), withDestinationURL: root.appendingPathComponent("Pico.app"))
            let roots = [root]
            expect(HubManifest.isInApplications(root.appendingPathComponent("Pico.app"), roots: roots))
            expect(HubManifest.isInApplications(root.appendingPathComponent("Alias.app"), roots: roots), "lien qui reste dans la racine")
            expect(!HubManifest.isInApplications(root.appendingPathComponent("Lien.app"), roots: roots), ".app en lien vers l'exterieur")
            expect(!HubManifest.isInApplications(root.appendingPathComponent("Dossier/Evil.app"), roots: roots), "dossier en lien vers l'exterieur")
            expect(!HubManifest.isInApplications(outside.appendingPathComponent("Evil.app"), roots: roots))
            // Racine elle-meme en lien symbolique : comparee resolue.
            let linkedRoot = dir.appendingPathComponent("RacineLien")
            try fm.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
            expect(HubManifest.isInApplications(root.appendingPathComponent("Pico.app"), roots: [linkedRoot]))
            expect(HubManifest.isInApplications(linkedRoot.appendingPathComponent("Pico.app"), roots: [root]))
        }
    },
    Test("applicationRoots") {
        let home = URL(fileURLWithPath: "/Users/a")
        expectEqual(HubManifest.applicationRoots(home: home).map(\.path), ["/Applications", "/Users/a/Applications"])
    },
])

let hubStatusTests: (String, [Test]) = ("HubStatus", [
    Test("actionVisibilityDefaultsToAlways") {
        let a = AppAction("new", title: "N", symbol: "plus")
        expectEqual(a.visible, .always)
        let text = String(decoding: try JSONEncoder().encode(a), as: UTF8.self)
        expect(!text.contains("visible"), "always n'est pas ecrit : fiche identique a la 0.2.5 : \(text)")
        let idle = AppAction("1h", title: "1 h", symbol: "sun.max", visible: .idle)
        let idleText = String(decoding: try JSONEncoder().encode(idle), as: UTF8.self)
        expect(idleText.contains("\"visible\":\"idle\""), idleText)
        expectEqual(try JSONDecoder().decode(AppAction.self, from: try JSONEncoder().encode(idle)), idle)
        let unknown = try JSONDecoder().decode(AppAction.self, from: Data(#"{"id":"a","title":"A","symbol":"x","visible":"nuit"}"#.utf8))
        expectEqual(unknown.visible, .always, "valeur inconnue : toujours")
        let absent = try JSONDecoder().decode(AppAction.self, from: Data(#"{"id":"a","title":"A","symbol":"x"}"#.utf8))
        expectEqual(absent.visible, .always)
    },
    Test("visibilityMatrix") {
        expect(AppActionVisibility.always.isShown(active: false))
        expect(AppActionVisibility.always.isShown(active: true))
        expect(AppActionVisibility.idle.isShown(active: false))
        expect(!AppActionVisibility.idle.isShown(active: true))
        expect(!AppActionVisibility.active.isShown(active: false))
        expect(AppActionVisibility.active.isShown(active: true))
    },
    Test("statusAndActiveRoundTrip") {
        var m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico",
                            actions: [AppAction("1h", title: "1 h", symbol: "sun.max", visible: .idle),
                                      AppAction("arreter", title: "Arr\u{00EA}ter", symbol: "stop.circle", visible: .active),
                                      AppAction("new", title: "N", symbol: "plus")])
        expectEqual(m.status, nil)
        expect(!m.active)
        let plain = String(decoding: try m.encoded(), as: UTF8.self)
        expect(!plain.contains("status"), "sans statut : champ absent")
        expectEqual(m.visibleActions.map(\.id), ["1h", "new"])
        m.status = "\u{00C9}veill\u{00E9} jusqu'\u{00E0} 15 h 40"
        m.active = true
        expectEqual(m.visibleActions.map(\.id), ["arreter", "new"])
        let data = try m.encoded()
        expectEqual(HubManifest.decode(data), m)
        let text = String(decoding: data, as: UTF8.self)
        expect(text.contains("\"active\" : true"), text)
        expect(text.contains("\"format\" : 1"), "format inchange")
    },
    Test("oldManifestsReadAsIdleWithoutStatus") {
        let json = """
        {"format": 1, "bundleIdentifier": "fr.vialet.pico", "name": "Pico", "displayName": "Pico",
         "version": "0.2.0", "appPath": "/Applications/Pico.app", "scheme": "pico", "repository": "avialet/pico",
         "site": "https://pico.vialet.app", "glyph": "", "strokeDeep": false,
         "palette": {"accent": "#2F6FEB", "background": "#2F6FEB", "deep": "#00001F", "pale": "#EBF2FF",
                     "night": "#0F1A2F", "nightInk": "#C4D8FD"},
         "actions": [{"id": "new", "title": "Nouvelle", "symbol": "plus"}]}
        """
        let m = HubManifest.decode(Data(json.utf8))
        expectEqual(m?.status, nil)
        expectEqual(m?.active, false)
        expectEqual(m?.visibleActions.map(\.id), ["new"])
    },
    Test("untrustedStatusIsBounded") {
        func decoded(_ status: String) -> String? {
            var m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico", actions: [])
            m.status = status
            return HubManifest.decode(try! m.encoded())?.status
        }
        expectEqual(decoded(String(repeating: "s", count: 60)), String(repeating: "s", count: 60))
        expectEqual(decoded(String(repeating: "s", count: 61)), nil, "plus de 60 caracteres : retire")
        expectEqual(decoded("deux\nlignes"), nil, "caractere de controle : retire")
        expectEqual(decoded("tab\tulation"), nil)
        expectEqual(decoded("\u{202E}inverse"), nil, "controle de direction : retire")
        expectEqual(decoded("   "), nil, "vide : retire")
        expectEqual(decoded("Actif"), "Actif")
    },
    Test("statusIsSanitizedWhenPublished") {
        expectEqual(HubManifest.sanitizedStatus(nil), nil)
        expectEqual(HubManifest.sanitizedStatus("  "), nil)
        expectEqual(HubManifest.sanitizedStatus(" deux\nlignes\t "), "deux lignes")
        let long = HubManifest.sanitizedStatus(String(repeating: "a", count: 80))
        expectEqual(long?.count, 60)
        expect(long?.hasSuffix("\u{2026}") == true, "coupe avec une ellipse")
    },
    Test("publishWithStatusRewritesTheManifest") {
        try MainActor.assumeIsolated {
            try withDirectory { dir in
                let actions = AppActions(pico, open: {})
                actions.register(AppAction("1h", title: "1 h", symbol: "sun.max", visible: .idle)) {}
                expect(actions.publish(force: true, directory: dir))
                let file = HubManifest.fileURL(bundleIdentifier: "fr.vialet.pico", in: dir)
                expectEqual(HubManifest.decode(try Data(contentsOf: file))?.status, nil)
                expect(actions.publish(status: "Actif\njusqu'au soir", active: true, force: true, directory: dir))
                expectEqual(actions.status, "Actif jusqu'au soir")
                expect(actions.isActive)
                var read = HubManifest.decode(try Data(contentsOf: file))
                expectEqual(read?.status, "Actif jusqu'au soir")
                expectEqual(read?.active, true)
                expectEqual(read?.visibleActions.count, 0)
                // Une republication simple garde le statut.
                expect(actions.publish(force: true, directory: dir))
                read = HubManifest.decode(try Data(contentsOf: file))
                expectEqual(read?.status, "Actif jusqu'au soir")
                expect(actions.publish(status: nil, active: false, force: true, directory: dir))
                read = HubManifest.decode(try Data(contentsOf: file))
                expectEqual(read?.status, nil)
                expectEqual(read?.active, false)
            }
        }
    },
    Test("actionTextsWithControlCharactersAreDropped") {
        var m = HubManifest(identity: pico, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico",
                            actions: [AppAction("a", title: "deux\nlignes", symbol: "plus"),
                                      AppAction("b", title: "\u{202E}inverse", symbol: "plus"),
                                      AppAction("c", title: "Ok", symbol: "plus", shortcut: "\u{2318}\tN"),
                                      AppAction("d", title: "Ok", symbol: "plus\u{0000}"),
                                      AppAction("e", title: "Nouvelle t\u{00E2}che", symbol: "plus", shortcut: "\u{2318}N")])
        m.status = nil
        expectEqual(HubManifest.decode(try m.encoded())?.actions.map(\.id), ["e"])
    },
])
