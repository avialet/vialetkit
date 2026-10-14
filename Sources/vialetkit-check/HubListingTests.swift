import Foundation
@testable import VialetKit

private func installed(_ name: String, display: String? = nil, version: String = "0.2.0", scheme: String? = nil) -> InstalledApp {
    InstalledApp(bundleIdentifier: "fr.vialet.\(name.lowercased())", name: name, displayName: display ?? name,
                 version: version, url: URL(fileURLWithPath: "/Applications/\(name).app"), scheme: scheme)
}

private let picoIdentity = AppIdentity(name: "Pico", displayName: "Pico", repository: "avialet/pico",
                                       bundleIdentifier: "fr.vialet.pico", palette: .sea, glyph: "M 20 50 L 80 50")

private let catalog = Catalog.parse(Data(catalogJSON.utf8))!

let listingTests: (String, [Test]) = ("Listing", [
    Test("ordersByCatalogThenAlphabetically") {
        let apps = [installed("Zebre"), installed("Chuchote"), installed("Allege", display: "All\u{00E8}ge"),
                    installed("Pico"), installed("Brouillon"), installed("Ane", display: "\u{00C2}ne")]
        let listing = HubListing.build(installed: apps, manifests: [], catalog: catalog)
        expectEqual(listing.apps.map(\.name), ["Pico", "Allege", "Chuchote", "Ane", "Brouillon", "Zebre"])
    },
    Test("alphabeticalWithoutCatalog") {
        let apps = [installed("Pico"), installed("Allege", display: "All\u{00E8}ge"), installed("Brouillon")]
        let listing = HubListing.build(installed: apps, manifests: [], catalog: nil)
        expectEqual(listing.apps.map(\.displayName), ["All\u{00E8}ge", "Brouillon", "Pico"])
        expectEqual(listing.discover, [])
    },
    Test("excludesVialetItself") {
        let listing = HubListing.build(installed: [installed("Vialet"), installed("Pico")], manifests: [], catalog: nil)
        expectEqual(listing.apps.map(\.name), ["Pico"])
    },
    Test("discoverListsAvailableCatalogAppsNotInstalled") {
        let listing = HubListing.build(installed: [installed("Pico")], manifests: [], catalog: catalog)
        expectEqual(listing.discover.map(\.brand), ["Allege", "Chuchote"])
    },
    Test("manifestEnrichesEntry") {
        let manifest = HubManifest(identity: picoIdentity, version: "0.2.0", appPath: "/Applications/Pico.app",
                                   scheme: "pico", actions: [AppAction("new", title: "Nouvelle t\u{00E2}che", symbol: "plus")])
        let listing = HubListing.build(installed: [installed("Pico", version: "0.2.1")], manifests: [manifest], catalog: catalog)
        let pico = listing.apps.first
        expectEqual(pico?.actions.map(\.id), ["new"])
        expectEqual(pico?.palette, AccentPalette.sea)
        expectEqual(pico?.glyph, "M 20 50 L 80 50")
        expectEqual(pico?.scheme, "pico")
        expectEqual(pico?.repository, "avialet/pico")
        expectEqual(pico?.version, "0.2.1", "la version installee prime sur celle de la fiche")
        expectEqual(pico?.tagline, "Le gestionnaire de t\u{00E2}ches.")
        expectEqual(pico?.site, URL(string: "https://pico.vialet.app"))
    },
    Test("defaultsWithoutManifest") {
        let listing = HubListing.build(installed: [installed("Allege", display: "All\u{00E8}ge", scheme: "allege")],
                                       manifests: [], catalog: nil)
        let allege = listing.apps.first
        expectEqual(allege?.actions, [])
        expectEqual(allege?.palette, nil)
        expectEqual(allege?.scheme, "allege")
        expectEqual(allege?.repository, "avialet/allege")
        expectEqual(allege?.site, URL(string: "https://allege.vialet.app"))
        expectEqual(allege?.tagline, nil)
    },
    Test("actionURLs") {
        let manifest = HubManifest(identity: picoIdentity, version: "0.2.0", appPath: "/Applications/Pico.app",
                                   scheme: "pico", actions: [AppAction("new", title: "Nouvelle", symbol: "plus")])
        let listing = HubListing.build(installed: [installed("Pico")], manifests: [manifest], catalog: nil)
        let pico = listing.apps[0]
        expectEqual(pico.url(for: "new"), URL(string: "pico://new"))
        expectEqual(pico.updateURL, URL(string: "pico://update"))
        let bare = HubListing.build(installed: [installed("Pince")], manifests: [], catalog: nil).apps[0]
        expectEqual(bare.updateURL, nil, "sans schema connu : pas d'URL")
    },
    Test("untrustedManifestFieldsAreValidated") {
        let evil = HubManifest(identity: AppIdentity(name: "Pico", displayName: "Pico", repository: "evil/../x",
                                                     bundleIdentifier: "fr.vialet.pico", palette: .sea, glyph: ""),
                               version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "https", actions: [])
        // Sans schema dans l'Info.plist, celui de la fiche est refuse s'il est systeme.
        let entry = HubListing.build(installed: [installed("Pico")], manifests: [evil], catalog: nil).apps[0]
        expectEqual(entry.repository, "avialet/pico", "depot invalide : repli")
        expectEqual(entry.scheme, nil, "schema systeme refuse")
        expectEqual(entry.updateURL, nil)
        let fileSite = AppIdentity(name: "Pico", displayName: "Pico", repository: "avialet/pico",
                                   bundleIdentifier: "fr.vialet.pico", palette: .sea, glyph: "",
                                   site: URL(string: "file:///etc/passwd")!)
        let m = HubManifest(identity: fileSite, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico", actions: [])
        expectEqual(HubListing.build(installed: [installed("Pico")], manifests: [m], catalog: nil).apps[0].site,
                    URL(string: "https://pico.vialet.app"), "site de la fiche non https : repli sur le site par defaut")
    },
    Test("infoPlistSchemeWinsOverManifest") {
        let other = HubManifest(identity: picoIdentity, version: "0.2.0", appPath: "/Applications/Pico.app",
                                scheme: "autre", actions: [AppAction("new", title: "N", symbol: "plus")])
        let entry = HubListing.build(installed: [installed("Pico", scheme: "pico")], manifests: [other], catalog: nil).apps[0]
        expectEqual(entry.scheme, "pico")
        expectEqual(entry.url(for: "new"), URL(string: "pico://new"))
        expectEqual(entry.url(for: "../x"), nil, "identifiant invalide")
        expectEqual(entry.url(for: "New"), nil)
    },
    Test("manifestSchemeAcceptedWhenSaneAndNoInfoPlistScheme") {
        let m = HubManifest(identity: picoIdentity, version: "0.2.0", appPath: "/Applications/Pico.app",
                            scheme: "pico", actions: [])
        expectEqual(HubListing.build(installed: [installed("Pico")], manifests: [m], catalog: nil).apps[0].scheme, "pico")
    },
    Test("invalidInfoPlistSchemeAndNameAreRejected") {
        let weird = InstalledApp(bundleIdentifier: "fr.vialet.x", name: "../X", displayName: "X", version: "1.0.0",
                                 url: URL(fileURLWithPath: "/Applications/X.app"), scheme: "file")
        let entry = HubListing.build(installed: [weird], manifests: [], catalog: nil).apps[0]
        expectEqual(entry.scheme, nil)
        expectEqual(entry.repository, nil, "nom inutilisable : aucun depot, aucune requete")
    },
    Test("statusAndVisibleActionsComeFromManifest") {
        var m = HubManifest(identity: picoIdentity, version: "0.2.0", appPath: "/Applications/Pico.app", scheme: "pico",
                            actions: [AppAction("1h", title: "1 h", symbol: "sun.max", visible: .idle),
                                      AppAction("stop", title: "Arr\u{00EA}ter", symbol: "stop.circle", visible: .active),
                                      AppAction("new", title: "N", symbol: "plus")])
        var entry = HubListing.build(installed: [installed("Pico")], manifests: [m], catalog: catalog).apps[0]
        expectEqual(entry.status, nil)
        expect(!entry.active)
        expectEqual(entry.visibleActions.map(\.id), ["1h", "new"])
        expectEqual(entry.subtitle, "Le gestionnaire de t\u{00E2}ches.", "sans statut : l'accroche")
        m.status = "\u{00C9}veill\u{00E9} jusqu'\u{00E0} 15 h 40"
        m.active = true
        entry = HubListing.build(installed: [installed("Pico")], manifests: [m], catalog: catalog).apps[0]
        expectEqual(entry.status, "\u{00C9}veill\u{00E9} jusqu'\u{00E0} 15 h 40")
        expect(entry.active)
        expectEqual(entry.visibleActions.map(\.id), ["stop", "new"])
        expectEqual(entry.subtitle, entry.status, "le statut remplace l'accroche")
        // Une fiche lue garde ses bornes : un statut trop long n'arrive jamais jusqu'au menu.
        m.status = String(repeating: "x", count: 200)
        let decoded = HubManifest.decode(try! m.encoded())!
        expectEqual(HubListing.build(installed: [installed("Pico")], manifests: [decoded], catalog: nil).apps[0].status, nil)
    },
])
