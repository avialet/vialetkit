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
])
