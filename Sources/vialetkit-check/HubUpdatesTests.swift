import Foundation
@testable import VialetKit

private func releaseJSON(tag: String, app: String, draft: Bool = false) -> Data {
    let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    return Data("""
    {"tag_name": "\(tag)", "body": "notes", "html_url": "https://github.com/avialet/x/releases/tag/\(tag)",
     "draft": \(draft), "prerelease": false,
     "assets": [{"name": "\(app)-\(v).dmg", "browser_download_url": "https://github.com/avialet/x/releases/download/\(tag)/\(app)-\(v).dmg"},
                {"name": "\(app)-\(v).dmg.sha256", "browser_download_url": "https://github.com/avialet/x/releases/download/\(tag)/\(app)-\(v).dmg.sha256"}]}
    """.utf8)
}

let updatesTests: (String, [Test]) = ("HubUpdates", [
    Test("newerReleaseIsAvailable") {
        expectEqual(HubUpdates.available(installed: "0.2.0", releaseJSON: releaseJSON(tag: "v0.3.0", app: "Pico"), appName: "Pico"),
                    SemanticVersion(0, 3, 0))
        expectEqual(HubUpdates.available(installed: "0.3.0", releaseJSON: releaseJSON(tag: "v0.3.0", app: "Pico"), appName: "Pico"), nil)
        expectEqual(HubUpdates.available(installed: "0.4.0", releaseJSON: releaseJSON(tag: "v0.3.0", app: "Pico"), appName: "Pico"), nil)
    },
    Test("incompleteReleasesAreIgnored") {
        // DMG d'une autre app, brouillon, version installee illisible : rien a annoncer.
        expectEqual(HubUpdates.available(installed: "0.2.0", releaseJSON: releaseJSON(tag: "v0.3.0", app: "Autre"), appName: "Pico"), nil)
        expectEqual(HubUpdates.available(installed: "0.2.0", releaseJSON: releaseJSON(tag: "v0.3.0", app: "Pico", draft: true), appName: "Pico"), nil)
        expectEqual(HubUpdates.available(installed: "dev", releaseJSON: releaseJSON(tag: "v0.3.0", app: "Pico"), appName: "Pico"), nil)
    },
    Test("scheduleLikeTheKit") {
        let now = Date(timeIntervalSince1970: 3_000_000)
        expect(HubUpdates.shouldCheck(now: now, lastCheck: nil))
        expect(!HubUpdates.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-29 * 60)))
        expect(HubUpdates.shouldCheck(now: now, lastCheck: now.addingTimeInterval(-30 * 60)))
        expect(HubUpdates.shouldCheck(now: now, lastCheck: now.addingTimeInterval(600)), "horloge reculee")
        expectEqual(HubUpdates.interval, 6 * 3600)
        expectEqual(HubUpdates.floor, 30 * 60)
    },
    Test("releaseURL") {
        expectEqual(HubUpdates.releaseURL(repository: "avialet/pico"),
                    URL(string: "https://api.github.com/repos/avialet/pico/releases/latest"))
    },
    Test("responseOutcome") {
        expectEqual(HubUpdates.outcome(status: 200), .result)
        expectEqual(HubUpdates.outcome(status: 404), .result, "aucune Release : a jour")
        expectEqual(HubUpdates.outcome(status: 304), .unchanged, "ETag : resultat precedent garde")
        expectEqual(HubUpdates.outcome(status: 403), .stop, "quota : on coupe")
        expectEqual(HubUpdates.outcome(status: 429), .stop)
        expectEqual(HubUpdates.outcome(status: 500), .skip, "erreur : app non interrogee")
        expectEqual(HubUpdates.outcome(status: 301), .skip)
    },
])
