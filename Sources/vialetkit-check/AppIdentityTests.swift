import Foundation
import VialetKit

let allegeIdentity = AppIdentity(
    name: "Allege", displayName: "All\u{00E8}ge", repository: "avialet/allege",
    bundleIdentifier: "fr.vialet.allege",
    palette: AccentPalette(accent: 0x2E9D6E, background: 0x2E9D6E, deep: 0x012B1A,
                           pale: 0xE1F8EB, night: 0x032114, nightInk: 0xB6E4CB),
    glyph: "M 50 16 L 50 60 M 32 42 L 50 60 L 68 42 M 24 82 L 76 82")

let appIdentityTests: (String, [Test]) = ("AppIdentity", [
    Test("urls") {
        expectEqual(allegeIdentity.siteURL, URL(string: "https://allege.vialet.app")!)
        expectEqual(allegeIdentity.repositoryURL, URL(string: "https://github.com/avialet/allege")!)
    },
    Test("siteOverride") {
        let hub = AppIdentity(name: "Vialet", displayName: "Vialet", repository: "avialet/vialet",
                              bundleIdentifier: "fr.vialet.vialet", palette: .sea, glyph: "",
                              site: URL(string: "https://vialet.app")!)
        expectEqual(hub.siteURL, URL(string: "https://vialet.app")!)
        let m = HubManifest(identity: hub, version: "0.1.0", appPath: "/Applications/Vialet.app", scheme: "vialet", actions: [])
        expectEqual(m.site, "https://vialet.app")
    },
    Test("credits") {
        expectEqual(allegeIdentity.author, "Aur\u{00E9}lien Vialet")
        expectEqual(allegeIdentity.license, "MIT")
        expect(!allegeIdentity.strokeDeep, "strokeDeep par defaut")
    },
    Test("keyPrefixesName") {
        expectEqual(allegeIdentity.key("HotKey"), "AllegeHotKey")
    },
    Test("updaterConfiguration") {
        let c = UpdaterConfiguration(allegeIdentity)
        expectEqual(c.repository, "avialet/allege")
        expectEqual(c.bundleIdentifier, "fr.vialet.allege")
        expectEqual(c.appName, "Allege")
        expectEqual(c.displayName, "All\u{00E8}ge")
        expectEqual(c.defaultsPrefix, "Allege")
    },
])
