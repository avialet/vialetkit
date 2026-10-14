import Foundation
@testable import VialetKit

/// Les fiches HubManifest et le catalogue ne sont pas dignes de confiance : chaque rejet est teste.
let safetyTests: (String, [Test]) = ("Safety", [
    Test("repositoryMustBeAvialet") {
        expect(HubSafety.isValidRepository("avialet/pico"))
        expect(HubSafety.isValidRepository("avialet/Pico_2.x-b"))
        expect(!HubSafety.isValidRepository("avialet/."))
        expect(!HubSafety.isValidRepository("avialet/.."))
        expect(!HubSafety.isValidRepository("autre/pico"), "autre proprietaire")
        expect(!HubSafety.isValidRepository("avialet/pico/../x"), "segment de plus")
        expect(!HubSafety.isValidRepository("avialet/"), "nom vide")
        expect(!HubSafety.isValidRepository("avialet/pi co"), "espace")
        expect(!HubSafety.isValidRepository("avialet/pi?co"), "requete")
        expect(!HubSafety.isValidRepository("avialet/pi#co"), "fragment")
        expect(!HubSafety.isValidRepository("avialet/p\u{00EF}co"), "non ASCII")
        expect(!HubSafety.isValidRepository("AVIALET/pico"), "proprietaire exact")
        expect(!HubSafety.isValidRepository("avialet/" + String(repeating: "a", count: 101)), "trop long")
    },
    Test("releaseURLOnlyForValidRepository") {
        expectEqual(HubUpdates.releaseURL(repository: "avialet/pico"),
                    URL(string: "https://api.github.com/repos/avialet/pico/releases/latest"))
        expectEqual(HubUpdates.releaseURL(repository: "avialet/.."), nil)
        expectEqual(HubUpdates.releaseURL(repository: "evil/x"), nil)
    },
    Test("schemeRules") {
        expect(HubSafety.isAcceptableScheme("pico"))
        expect(HubSafety.isAcceptableScheme("allege2"))
        expect(HubSafety.isAcceptableScheme("a+b.c-d"))
        expect(!HubSafety.isAcceptableScheme(""), "vide")
        expect(!HubSafety.isAcceptableScheme("2pico"), "chiffre initial")
        expect(!HubSafety.isAcceptableScheme("Pico"), "majuscule")
        expect(!HubSafety.isAcceptableScheme("pi co"), "espace")
        expect(!HubSafety.isAcceptableScheme("pico:"), "deux-points")
        expect(!HubSafety.isAcceptableScheme(String(repeating: "a", count: 32)), "plus de 31 caracteres")
        expect(HubSafety.isAcceptableScheme(String(repeating: "a", count: 31)))
        for system in ["file", "http", "https", "ftp", "mailto", "tel", "sms", "facetime", "ssh", "smb", "afp", "vnc",
                       "javascript", "data", "about", "x-apple-systempreferences", "shortcuts", "applescript", "itms-apps",
                       "x-help-action", "help", "news", "message", "webcal", "ical", "maps", "music", "spotlight"] {
            expect(!HubSafety.isAcceptableScheme(system), "schema systeme \(system)")
        }
    },
    Test("manifestLocationMustBeAnAppInApplications") {
        let home = URL(fileURLWithPath: "/Users/a")
        func ok(_ path: String) -> Bool { HubSafety.isAcceptableAppPath(path, home: home) }
        expect(ok("/Applications/Pico.app"))
        expect(ok("/Applications/Outils/Pico.app"))
        expect(ok("/Users/a/Applications/Pico.app"))
        expect(!ok("/Applications/Pico"), "sans .app")
        expect(!ok("/Applications/script.sh"), "pas une app")
        expect(!ok("/Users/a/Downloads/Pico.app"), "hors Applications")
        expect(!ok("/tmp/Pico.app"))
        expect(!ok("/Applications/../tmp/Pico.app"), "remontee")
        expect(!ok("Pico.app"), "chemin relatif")
        expect(!ok(""))
    },
    Test("catalogOverOneMegabyteIsIgnored") {
        expectEqual(Catalog.maxSize, 1024 * 1024)
        var data = Data(catalogJSON.utf8)
        expect(Catalog.parse(data) != nil)
        data.append(Data(repeating: 0x20, count: Catalog.maxSize))
        expectEqual(Catalog.parse(data), nil)
    },
    Test("catalogCacheReadChecksSizeFirst") {
        try withTemporaryDirectory { dir in
            let small = dir.appendingPathComponent("petit.json")
            try Data(catalogJSON.utf8).write(to: small)
            expectEqual(Catalog.load(from: small)?.count, 4)
            let big = dir.appendingPathComponent("gros.json")
            var data = Data(catalogJSON.utf8)
            data.append(Data(repeating: 0x20, count: Catalog.maxSize))
            try data.write(to: big)
            expectEqual(Catalog.load(from: big), nil)
            expectEqual(Catalog.load(from: dir.appendingPathComponent("absent.json")), nil)
        }
    },
    Test("updatesMergeKeepsUncheckedApps") {
        let previous = ["fr.vialet.a": SemanticVersion(1), "fr.vialet.b": SemanticVersion(2), "fr.vialet.c": SemanticVersion(3)]
        // a et b interroges (a a jour, b en 2.1), c non interroge (quota) : c garde sa valeur.
        let merged = HubUpdates.merge(previous: previous, found: ["fr.vialet.b": SemanticVersion(2, 1)],
                                      checked: ["fr.vialet.a", "fr.vialet.b"])
        expectEqual(merged, ["fr.vialet.b": SemanticVersion(2, 1), "fr.vialet.c": SemanticVersion(3)])
    },
    Test("symlinksLeavingApplicationsAreRejected") {
        try withTemporaryDirectory { dir in
            let fm = FileManager.default
            let root = dir.appendingPathComponent("Applications"), outside = dir.appendingPathComponent("Ailleurs")
            try makeBundle(in: root, name: "Pico", bundleId: "fr.vialet.pico")
            try makeBundle(in: outside, name: "Evil", bundleId: "fr.vialet.pico")
            try makeBundle(in: outside.appendingPathComponent("Dossier"), name: "Evil", bundleId: "fr.vialet.pico")
            try fm.createSymbolicLink(at: root.appendingPathComponent("Lien.app"), withDestinationURL: outside.appendingPathComponent("Evil.app"))
            try fm.createSymbolicLink(at: root.appendingPathComponent("Dossier"), withDestinationURL: outside.appendingPathComponent("Dossier"))
            let roots = [root]
            expect(HubSafety.isAcceptableAppURL(root.appendingPathComponent("Pico.app"), roots: roots))
            expect(!HubSafety.isAcceptableAppURL(root.appendingPathComponent("Lien.app"), roots: roots), ".app en lien vers l'exterieur")
            expect(!HubSafety.isAcceptableAppURL(root.appendingPathComponent("Dossier/Evil.app"), roots: roots), "dossier en lien")
            expect(!HubSafety.isAcceptableAppURL(outside.appendingPathComponent("Evil.app"), roots: roots))
            expect(!HubSafety.isAcceptableAppURL(root, roots: roots), "pas un .app")
            expect(HubSafety.isAcceptableAppPath(root.appendingPathComponent("Pico.app").path, roots: roots))
            expect(!HubSafety.isAcceptableAppPath(root.appendingPathComponent("Lien.app").path, roots: roots))
            // Le parcours ecarte les liens qui sortent des racines avant la deduplication : le lien vers
            // une autre copie du meme bundle ne masque pas la vraie app.
            let found = InstalledApp.scan(directories: [root]) { HubSafety.isAcceptableAppURL($0, roots: roots) }
            expectEqual(found.map { $0.url.lastPathComponent }, ["Pico.app"])
        }
    },
    Test("catalogCacheMustBeRegularFile") {
        withTemporaryDirectory { dir in
            let fifo = dir.appendingPathComponent("fifo.json")
            expectEqual(mkfifo(fifo.path, 0o600), 0)
            expectEqual(Catalog.load(from: fifo), nil, "FIFO : refuse sans bloquer")
            expectEqual(Catalog.load(from: dir), nil, "dossier")
        }
    },
    Test("infoPlistMustBeRegularAndSmall") {
        try withTemporaryDirectory { dir in
            let big = try makeBundle(in: dir, name: "Gros", bundleId: "fr.vialet.gros")
            let plist = big.appendingPathComponent("Contents/Info.plist")
            var data = try Data(contentsOf: plist)
            data.append(Data(repeating: 0x20, count: InstalledApp.maxInfoPlistSize))
            try data.write(to: plist)
            expectEqual(InstalledApp.read(bundleURL: big), nil, "Info.plist > 1 Mo")
            let fifoApp = dir.appendingPathComponent("Fifo.app/Contents")
            try FileManager.default.createDirectory(at: fifoApp, withIntermediateDirectories: true)
            expectEqual(mkfifo(fifoApp.appendingPathComponent("Info.plist").path, 0o600), 0)
            expectEqual(InstalledApp.read(bundleURL: dir.appendingPathComponent("Fifo.app")), nil, "FIFO")
            expectEqual(InstalledApp.maxInfoPlistSize, 1024 * 1024)
        }
    },
    Test("responseSizeIsBounded") {
        expectEqual(HubSafety.maxResponseSize, 2 * 1024 * 1024)
        expect(HubSafety.isAcceptableResponse(byteCount: 10, expectedLength: -1))
        expect(HubSafety.isAcceptableResponse(byteCount: HubSafety.maxResponseSize, expectedLength: -1))
        expect(!HubSafety.isAcceptableResponse(byteCount: HubSafety.maxResponseSize + 1, expectedLength: -1))
        expect(!HubSafety.isAcceptableResponse(byteCount: 0, expectedLength: Int64(HubSafety.maxResponseSize) + 1), "annonce trop grosse")
    },
])
