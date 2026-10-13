import AppKit
import Foundation
import SwiftUI
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
    Test("noticeModeFollowsUpdater") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                defaults.set("0.1.0", forKey: "AllegeLastSeenVersion")
                let updater = Updater(configuration: configuration, defaults: defaults, currentVersion: SemanticVersion(0, 2, 0))
                expectEqual(UpdateNotice.mode(for: updater), .updated(SemanticVersion(0, 2, 0), nil))
                let release = sample(SemanticVersion(0, 3, 0))
                updater.apply(latest: release)
                expectEqual(UpdateNotice.mode(for: updater), .available(release), "la version nouvelle passe avant")
                updater.dismissAvailable()
                expectEqual(UpdateNotice.mode(for: updater), .updated(SemanticVersion(0, 2, 0), nil))
                updater.acknowledgeUpdate()
                expect(UpdateNotice.mode(for: updater) == nil, "rien a annoncer")
            }
        }
    },
    Test("noticeShowsInstallFailureOnly") {
        MainActor.assumeIsolated {
            let updater = Updater(configuration: configuration, defaults: nil, currentVersion: SemanticVersion(0, 2, 0))
            let release = sample(SemanticVersion(0, 3, 0))
            updater.apply(latest: release)
            updater.fail(installing: release, message: "Corrompu")
            expectEqual(UpdateNotice.mode(for: updater), .failure("Corrompu"))
            updater.dismissAvailable()
            expect(UpdateNotice.mode(for: updater) == nil, "Plus tard ecarte aussi apres un echec")
            expect(updater.available != nil)
            updater.dismissError()
            updater.fail(installing: nil, message: "GitHub a repondu 500.")
            expect(UpdateNotice.mode(for: updater) == nil, "echec d'une recherche : pas dans le bandeau")
        }
    },
    Test("noticeKindIgnoresProgress") {
        expectEqual(UpdateNotice.Mode.progress(.downloading(0.1)).kind, UpdateNotice.Mode.progress(.downloading(0.9)).kind)
        expect(UpdateNotice.Mode.progress(.verifying).kind != UpdateNotice.Mode.failure("x").kind)
    },
    Test("standardScenariosIncludeUpdate") {
        MainActor.assumeIsolated {
            let names = SnapshotRunner.standardScenarios(mainWindow: { nil }, identity: identity).map(\.name)
            expectEqual(names, ["mainWindow", "settings", "about", "floatingPanel", "update"])
        }
    },
    Test("updatePreviewWindowShowsThreeNotices") {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let window = SnapshotRunner.updateNoticeWindow(configuration, current: SemanticVersion(0, 2, 0))
            let size = window.contentView?.fittingSize ?? .zero
            expectEqual(size.width, 620)
            // Trois bandeaux d'au moins 46 pt, dont un deplie.
            expect(size.height > 3 * 46 + 40, "hauteur \(size.height)")
        }
    },
    Test("hiddenNoticeTakesNoSpace") {
        MainActor.assumeIsolated {
            _ = NSApplication.shared
            let updater = Updater(configuration: configuration, defaults: nil, currentVersion: SemanticVersion(0, 2, 0))
            let host = NSHostingView(rootView: UpdateNotice(updater: updater).frame(width: 400))
            expectEqual(host.fittingSize.height, 0)
            updater.apply(latest: sample(SemanticVersion(0, 3, 0)))
            let shown = NSHostingView(rootView: UpdateNotice(updater: updater).frame(width: 400))
            expect(shown.fittingSize.height > 40, "hauteur \(shown.fittingSize.height)")
        }
    },
    Test("updatedNotesFetchedOnlyWhenCheckSkipped") {
        let v = SemanticVersion(0, 2, 0)
        expect(!Updater.shouldFetchUpdatedNotes(updatedVersion: v, hasNotes: false, autoCheck: true, willCheck: true),
               "la verification remplira les notes")
        expect(Updater.shouldFetchUpdatedNotes(updatedVersion: v, hasNotes: false, autoCheck: true, willCheck: false),
               "verification sautee par le plancher")
        expect(!Updater.shouldFetchUpdatedNotes(updatedVersion: v, hasNotes: true, autoCheck: true, willCheck: false))
        expect(!Updater.shouldFetchUpdatedNotes(updatedVersion: v, hasNotes: false, autoCheck: false, willCheck: false))
        expect(!Updater.shouldFetchUpdatedNotes(updatedVersion: nil, hasNotes: false, autoCheck: true, willCheck: false))
    },
])
