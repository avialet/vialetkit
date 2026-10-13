import Foundation
@testable import VialetKit

/// Defaults jetables : un domaine par test, efface a la fin.
private func withDefaults(_ body: (UserDefaults) -> Void) {
    let suite = "VialetKitCheck.MenuBar.\(UInt32.random(in: 0...UInt32.max))"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    body(defaults)
}

private let identity = AppIdentity(name: "Essai", displayName: "Essai", repository: "avialet/essai",
                                   bundleIdentifier: "fr.vialet.essai", palette: .sea, glyph: "")

/// Localisateur de Vialet pilote par le test.
@MainActor
private final class FakeHub {
    var installed = false
}

let menuBarPresenceTests: (String, [Test]) = ("MenuBarPresence", [
    Test("migratesLegacyBoolean") {
        expectEqual(MenuBarMode.resolve(stored: nil, legacyVisible: nil), .auto)
        expectEqual(MenuBarMode.resolve(stored: nil, legacyVisible: true), .auto)
        expectEqual(MenuBarMode.resolve(stored: nil, legacyVisible: false), .hidden)
    },
    Test("storedModeWinsOverLegacy") {
        expectEqual(MenuBarMode.resolve(stored: "shown", legacyVisible: false), .shown)
        expectEqual(MenuBarMode.resolve(stored: "hidden", legacyVisible: true), .hidden)
        expectEqual(MenuBarMode.resolve(stored: "auto", legacyVisible: false), .auto)
        // Valeur inconnue : comme si rien n'etait range.
        expectEqual(MenuBarMode.resolve(stored: "toujours", legacyVisible: false), .hidden)
        expectEqual(MenuBarMode.resolve(stored: "", legacyVisible: nil), .auto)
    },
    Test("insertionMatrix") {
        expect(MenuBarMode.auto.isInserted(hubInstalled: false))
        expect(!MenuBarMode.auto.isInserted(hubInstalled: true))
        expect(MenuBarMode.shown.isInserted(hubInstalled: true))
        expect(MenuBarMode.shown.isInserted(hubInstalled: false))
        expect(!MenuBarMode.hidden.isInserted(hubInstalled: false))
        expect(!MenuBarMode.hidden.isInserted(hubInstalled: true))
    },
    Test("labelsAreFrench") {
        expectEqual(MenuBarMode.allCases, [.auto, .shown, .hidden])
        expectEqual(MenuBarMode.auto.label, "Automatique")
        expectEqual(MenuBarMode.shown.label, "Toujours")
        expectEqual(MenuBarMode.hidden.label, "Jamais")
    },
    Test("hubLocationOutsideTrashOnly") {
        expect(MenuBarPresence.isUsableHubLocation(URL(fileURLWithPath: "/Applications/Vialet.app")))
        expect(MenuBarPresence.isUsableHubLocation(URL(fileURLWithPath: "/Users/a/Applications/Vialet.app")))
        expect(!MenuBarPresence.isUsableHubLocation(URL(fileURLWithPath: "/Users/a/.Trash/Vialet.app")))
        expect(!MenuBarPresence.isUsableHubLocation(URL(fileURLWithPath: "/Volumes/Disque/.Trashes/501/Vialet.app")))
        expect(!MenuBarPresence.isUsableHubLocation(nil))
    },
    Test("constants") {
        expectEqual(MenuBarPresence.hubBundleIdentifier, "fr.vialet.vialet")
        expectEqual(MenuBarPresence.hubChangedNotification.rawValue, "fr.vialet.hub.changed")
    },
    Test("migratesAndPersistsOnInit") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                defaults.set(false, forKey: "EssaiMenuBar")
                let presence = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
                expectEqual(presence.mode, .hidden)
                expectEqual(defaults.string(forKey: "EssaiMenuBarMode"), "hidden")
                expect(!presence.isInserted)
            }
            withDefaults { defaults in
                let presence = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
                expectEqual(presence.mode, .auto)
                expectEqual(defaults.string(forKey: "EssaiMenuBarMode"), "auto")
                expect(presence.isInserted)
            }
        }
    },
    Test("autoFollowsHubOnRefresh") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let hub = FakeHub()
                let presence = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { hub.installed }, observe: false)
                expect(presence.isInserted, "sans Vialet, l'icone est la")
                hub.installed = true
                expect(presence.isInserted, "rien ne change avant refresh")
                presence.refresh()
                expect(presence.hubInstalled)
                expect(!presence.isInserted, "Vialet installee : icone masquee")
                presence.mode = .shown
                expect(presence.isInserted)
                expectEqual(defaults.string(forKey: "EssaiMenuBarMode"), "shown")
            }
        }
    },
    Test("systemRemovalBecomesHidden") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let presence = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
                // Cmd-glisser l'icone hors de la barre : le systeme ecrit false dans le binding.
                presence.isInserted = false
                expectEqual(presence.mode, .hidden)
                presence.isInserted = true
                expectEqual(presence.mode, .shown)
                // Ecrire la valeur courante ne change pas le mode.
                presence.mode = .auto
                presence.isInserted = true
                expectEqual(presence.mode, .auto)
                presence.binding.wrappedValue = false
                expectEqual(presence.mode, .hidden)
                expect(!presence.binding.wrappedValue)
            }
        }
    },
    Test("statusTextExplainsAuto") {
        expectEqual(MenuBarMode.auto.status(hubInstalled: true, hubName: "Vialet"),
                    "Masqu\u{00E9}e : Vialet est install\u{00E9}e et rassemble les apps.")
        expectEqual(MenuBarMode.auto.status(hubInstalled: false, hubName: "Vialet"),
                    "Visible tant que Vialet n'est pas install\u{00E9}e.")
        expectEqual(MenuBarMode.shown.status(hubInstalled: true, hubName: "Vialet"), "")
    },
])
