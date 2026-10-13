import Foundation
@testable import VialetKit

private let identity = AppIdentity(name: "Allege", displayName: "All\u{00E8}ge", repository: "avialet/allege",
                                   bundleIdentifier: "fr.vialet.allege", palette: .sea, glyph: "M 10 10 L 90 90")
private let configuration = UpdaterConfiguration(identity)

/// Domaine UserDefaults jetable, efface apres usage.
private func withDefaults(_ body: (UserDefaults) -> Void) {
    let name = "vialetkit-check-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    body(defaults)
    defaults.removePersistentDomain(forName: name)
}

private func sample(_ version: SemanticVersion, notes: String = "- A\n- B") -> ReleaseInfo {
    ReleaseInfo.sample(configuration, version: version, notes: notes)
}

let updateNoticeTests: (String, [Test]) = ("UpdateNotice", [
    Test("configurationCarriesGlyphAndKeys") {
        expectEqual(configuration.glyph, "M 10 10 L 90 90")
        expectEqual(configuration.dismissedKey, "AllegeDismissedUpdate")
        expectEqual(configuration.lastSeenKey, "AllegeLastSeenVersion")
        expectEqual(configuration.releaseURL(tag: SemanticVersion(0, 3, 0)).absoluteString,
                    "https://api.github.com/repos/avialet/allege/releases/tags/v0.3.0")
        let bare = UpdaterConfiguration(repository: "a/b", appName: "B", bundleIdentifier: "x.b")
        expectEqual(bare.glyph, "")
    },
    Test("announceUnlessDismissed") {
        let v3 = SemanticVersion(0, 3, 0)
        expect(Updater.shouldAnnounce(v3, dismissed: nil))
        expect(!Updater.shouldAnnounce(v3, dismissed: v3), "version ecartee")
        expect(Updater.shouldAnnounce(SemanticVersion(0, 3, 1), dismissed: v3), "la suivante reapparait")
    },
    Test("justUpdatedDecision") {
        let v1 = SemanticVersion(0, 1, 0), v2 = SemanticVersion(0, 2, 0)
        expect(Updater.justUpdated(current: v2, lastSeen: v1, hasRunBefore: true))
        expect(Updater.justUpdated(current: v2, lastSeen: v1, hasRunBefore: false))
        expect(!Updater.justUpdated(current: v2, lastSeen: v2, hasRunBefore: true))
        expect(!Updater.justUpdated(current: v1, lastSeen: v2, hasRunBefore: true), "retour en arriere")
        expect(Updater.justUpdated(current: v2, lastSeen: nil, hasRunBefore: true), "app d'avant la cle")
        expect(!Updater.justUpdated(current: v2, lastSeen: nil, hasRunBefore: false), "premiere installation")
        expect(!Updater.justUpdated(current: SemanticVersion(0), lastSeen: nil, hasRunBefore: true), "version inconnue")
    },
    Test("laterDismissesThisVersionOnly") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let updater = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                updater.apply(latest: sample(SemanticVersion(0, 3, 0)))
                expectEqual(updater.announced?.version, SemanticVersion(0, 3, 0))
                updater.dismissAvailable()
                expect(updater.announced == nil)
                expect(updater.available != nil, "la carte des Reglages la propose toujours")
                expectEqual(defaults.string(forKey: "AllegeDismissedUpdate"), "0.3.0")

                let relaunched = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                relaunched.apply(latest: sample(SemanticVersion(0, 3, 0)))
                expect(relaunched.announced == nil, "ecartee d'un lancement a l'autre")
                relaunched.apply(latest: sample(SemanticVersion(0, 4, 0)))
                expectEqual(relaunched.announced?.version, SemanticVersion(0, 4, 0))
            }
        }
    },
    Test("whatsNewAfterUpdate") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                defaults.set("0.1.0", forKey: "AllegeLastSeenVersion")
                let updater = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                expectEqual(updater.updatedVersion, SemanticVersion(0, 2, 0))
                expect(updater.updatedNotes == nil)
                // La derniere Release est la version installee : ses notes servent au bandeau.
                updater.apply(latest: sample(SemanticVersion(0, 2, 0), notes: "## Allege 0.2.0\n\n- Nouveau"))
                expectEqual(updater.updatedNotes?.bullets, ["Nouveau"])
                expect(updater.announced == nil)
                updater.acknowledgeUpdate()
                expect(updater.updatedVersion == nil)
                expectEqual(defaults.string(forKey: "AllegeLastSeenVersion"), "0.2.0")
                let again = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                expect(again.updatedVersion == nil, "une seule fois")
            }
        }
    },
    Test("firstInstallRecordsVersionSilently") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let updater = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                expect(updater.updatedVersion == nil)
                expectEqual(defaults.string(forKey: "AllegeLastSeenVersion"), "0.2.0")
            }
        }
    },
    Test("previousRunWithoutKeyCountsAsUpdate") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                defaults.set(Date(), forKey: "AllegeLastUpdateCheck")
                let updater = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                expectEqual(updater.updatedVersion, SemanticVersion(0, 2, 0))
            }
        }
    },
    Test("previewUpdaterWritesNothing") {
        MainActor.assumeIsolated {
            let updater = Updater(configuration: configuration, defaults: nil, currentVersion: SemanticVersion(0, 2, 0))
            updater.apply(latest: sample(SemanticVersion(0, 3, 0)))
            expectEqual(updater.announced?.version, SemanticVersion(0, 3, 0))
            updater.dismissAvailable()
            expect(updater.announced == nil)
            expect(updater.autoCheck)
        }
    },
    Test("sampleReleaseIsWellFormed") {
        let r = sample(SemanticVersion(0, 3, 0))
        expectEqual(r.dmgName, "Allege-0.3.0.dmg")
        expectEqual(r.pageURL.absoluteString, "https://github.com/avialet/allege/releases/tag/v0.3.0")
        expectEqual(r.releaseNotes.bullets, ["A", "B"])
    },
])
