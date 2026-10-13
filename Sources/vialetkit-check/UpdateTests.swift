import Foundation
import VialetKit

private func release(app: String = "Pico", tag: String = "v0.2.0", draft: Bool = false, prerelease: Bool = false,
                     assets: [(String, String)]? = nil) -> Data {
    let dl = "https://github.com/avialet/\(app.lowercased())/releases/download/\(tag)/"
    let list = assets ?? [("\(app)-0.2.0.dmg", dl + "\(app)-0.2.0.dmg"), ("\(app)-0.2.0.dmg.sha256", dl + "\(app)-0.2.0.dmg.sha256")]
    let items = list.map { "{\"name\":\"\($0.0)\",\"browser_download_url\":\"\($0.1)\"}" }.joined(separator: ",")
    return Data("""
    {"tag_name":"\(tag)","body":"Nouveautes","html_url":"https://github.com/avialet/\(app.lowercased())/releases/tag/\(tag)",
     "draft":\(draft),"prerelease":\(prerelease),"assets":[\(items)]}
    """.utf8)
}

let updateTests: (String, [Test]) = ("Update", [
    Test("semverParsing") {
        expectEqual(SemanticVersion(string: "0.2.0"), SemanticVersion(0, 2, 0))
        expectEqual(SemanticVersion(string: "v1.4.7"), SemanticVersion(1, 4, 7))
        expectEqual(SemanticVersion(string: "V2"), SemanticVersion(2, 0, 0))
        expectEqual(SemanticVersion(string: "1.2"), SemanticVersion(1, 2, 0))
        expectEqual(SemanticVersion(string: " 0.1.0\n"), SemanticVersion(0, 1, 0))
        for bad in ["", "v", "1.2.3.4", "1..3", "a.b.c", "1.0.0-beta", "1.-2.0", "١.٢.٣", "1.2.x"] {
            expect(SemanticVersion(string: bad) == nil, "devrait etre refuse : \(bad)")
        }
        expectEqual(SemanticVersion(1, 2, 3).description, "1.2.3")
    },
    Test("semverOrdering") {
        expect(SemanticVersion(0, 10, 0) > SemanticVersion(0, 9, 0), "0.10.0 > 0.9.0")
        expect(SemanticVersion(1, 0, 0) > SemanticVersion(0, 99, 99))
        expect(SemanticVersion(0, 1, 1) > SemanticVersion(0, 1, 0))
        expect(!(SemanticVersion(0, 1, 0) > SemanticVersion(0, 1, 0)))
        expect(SemanticVersion(string: "v0.2.0")! > SemanticVersion(string: "0.1.9")!)
    },
    Test("parseValidRelease") {
        let info = ReleaseInfo.parse(json: release(), appName: "Pico")
        expectEqual(info?.version, SemanticVersion(0, 2, 0))
        expectEqual(info?.dmgName, "Pico-0.2.0.dmg")
        expectEqual(info?.notes, "Nouveautes")
        expectEqual(info?.dmgURL.host, "github.com")
        expectEqual(info?.checksumURL.lastPathComponent, "Pico-0.2.0.dmg.sha256")
    },
    Test("parseUsesAppNameForAssets") {
        let info = ReleaseInfo.parse(json: release(app: "Allege"), appName: "Allege")
        expectEqual(info?.dmgName, "Allege-0.2.0.dmg")
        expect(ReleaseInfo.parse(json: release(app: "Allege"), appName: "Pico") == nil, "assets d'une autre app")
    },
    Test("parseRejectsUnsafeOrIncomplete") {
        expect(ReleaseInfo.parse(json: release(draft: true), appName: "Pico") == nil, "brouillon")
        expect(ReleaseInfo.parse(json: release(prerelease: true), appName: "Pico") == nil, "pre-version")
        expect(ReleaseInfo.parse(json: release(tag: "nightly"), appName: "Pico") == nil, "tag non version")
        expect(ReleaseInfo.parse(json: release(assets: [("Pico-0.2.0.dmg", "https://github.com/x/Pico-0.2.0.dmg")]), appName: "Pico") == nil, "checksum absent")
        expect(ReleaseInfo.parse(json: release(assets: [("Pico-0.1.0.dmg", "https://github.com/a/Pico-0.1.0.dmg"),
                                                        ("Pico-0.1.0.dmg.sha256", "https://github.com/a/s")]), appName: "Pico") == nil, "DMG d'une autre version")
        expect(ReleaseInfo.parse(json: release(assets: [("Pico-0.2.0.dmg", "http://github.com/a/Pico-0.2.0.dmg"),
                                                        ("Pico-0.2.0.dmg.sha256", "https://github.com/a/s")]), appName: "Pico") == nil, "http refuse")
        expect(ReleaseInfo.parse(json: release(assets: [("Pico-0.2.0.dmg", "https://evil.example.com/Pico-0.2.0.dmg"),
                                                        ("Pico-0.2.0.dmg.sha256", "https://github.com/a/s")]), appName: "Pico") == nil, "hote inconnu")
        expect(ReleaseInfo.parse(json: Data("pas du json".utf8), appName: "Pico") == nil)
        expect(ReleaseInfo.parse(json: Data("{}".utf8), appName: "Pico") == nil)
    },
    Test("parseChecksum") {
        let hash = String(repeating: "ab", count: 32)
        expectEqual(ReleaseInfo.parseChecksum("\(hash)  Pico-0.2.0.dmg\n", fileName: "Pico-0.2.0.dmg"), hash)
        expectEqual(ReleaseInfo.parseChecksum("\(hash.uppercased())  Pico-0.2.0.dmg"), hash)
        expectEqual(ReleaseInfo.parseChecksum("\(hash) *Pico-0.2.0.dmg", fileName: "Pico-0.2.0.dmg"), hash)
        expect(ReleaseInfo.parseChecksum("\(hash)  Autre.dmg", fileName: "Pico-0.2.0.dmg") == nil, "mauvais fichier")
        expect(ReleaseInfo.parseChecksum("abc  Pico-0.2.0.dmg") == nil, "hash trop court")
        expect(ReleaseInfo.parseChecksum(String(repeating: "z", count: 64)) == nil, "pas hexadecimal")
        expect(ReleaseInfo.parseChecksum("") == nil)
    },
    Test("updaterConfigurationDefaultsPrefix") {
        let c = UpdaterConfiguration(repository: "avialet/allege", appName: "Allege", bundleIdentifier: "fr.vialet.allege")
        expectEqual(c.defaultsPrefix, "Allege")
        expectEqual(c.releaseURL.absoluteString, "https://api.github.com/repos/avialet/allege/releases/latest")
    },
    Test("statusTextNamesTheApp") {
        expectEqual(UpdateText.status(.upToDate, appName: "Allège"), "Allège est à jour.")
        expectEqual(UpdateText.status(.installing, appName: "Allège"), "Installation, Allège va se relancer…")
        expectEqual(UpdateText.status(.idle, appName: "X"), "")
        expectEqual(UpdateText.status(.downloading(0.5), appName: "X"), "Téléchargement… 50 %")
    },
])
