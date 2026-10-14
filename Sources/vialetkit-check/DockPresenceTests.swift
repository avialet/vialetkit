import AppKit
@testable import VialetKit

private func withDefaults(_ body: (UserDefaults) -> Void) {
    let suite = "VialetKitCheck.Dock.\(UInt32.random(in: 0...UInt32.max))"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    body(defaults)
}

private let identity = AppIdentity(name: "Essai", displayName: "Essai", repository: "avialet/essai",
                                   bundleIdentifier: "fr.vialet.essai", palette: .sea, glyph: "")

/// Fenetre principale ouverte.
private let mainWindow = DockWindow(isVisible: true, isMiniaturized: false, isTitled: true, isNormalLevel: true, isAuxiliary: false)

/// Etat de l'app pilote par le test : fenetres, masquage, politique appliquee, activations.
@MainActor
private final class FakeApp {
    var windows: [DockWindow] = []
    var hidden = false
    var applied: [Bool] = []
    var activations = 0

    func presence(_ defaults: UserDefaults, loginItem: Bool = false) -> DockPresence {
        DockPresence(app: identity, defaults: defaults, windows: { self.windows }, isHidden: { self.hidden },
                     apply: { self.applied.append($0) }, activate: { self.activations += 1 },
                     launchedAsLoginItem: loginItem, observe: false)
    }
}

let dockPresenceTests: (String, [Test]) = ("DockPresence", [
    Test("modesAndLabels") {
        expectEqual(DockMode.allCases, [.whileWindowOpen, .always])
        expectEqual(DockMode.whileWindowOpen.label, "Fen\u{00EA}tre ouverte")
        expectEqual(DockMode.always.label, "Toujours")
        expectEqual(DockMode.resolve(stored: nil), .whileWindowOpen)
        expectEqual(DockMode.resolve(stored: "always"), .always)
        expectEqual(DockMode.resolve(stored: "jamais"), .whileWindowOpen, "valeur inconnue : defaut")
    },
    Test("whichWindowsCount") {
        expect(mainWindow.counts)
        var w = mainWindow
        w.isVisible = false
        expect(!w.counts, "fenetre fermee")
        w.isMiniaturized = true
        expect(w.counts, "fenetre dans le Dock : l'icone reste")
        w = mainWindow; w.isTitled = false
        expect(!w.counts, "sans barre de titre (panneau, icone de barre des menus)")
        w = mainWindow; w.isNormalLevel = false
        expect(!w.counts, "niveau flottant ou menu")
        w = mainWindow; w.isAuxiliary = true
        expect(!w.counts, "FloatingPanel, MenuBarExtra")
    },
    Test("decisionIsPure") {
        let panel = DockWindow(isVisible: true, isMiniaturized: false, isTitled: false, isNormalLevel: false, isAuxiliary: true)
        expect(!DockMode.whileWindowOpen.showsIcon(windows: []))
        expect(!DockMode.whileWindowOpen.showsIcon(windows: [panel]))
        expect(DockMode.whileWindowOpen.showsIcon(windows: [panel, mainWindow]))
        expect(DockMode.always.showsIcon(windows: []))
        expectEqual(DockMode.whileWindowOpen.activationPolicy(windows: []), .accessory)
        expectEqual(DockMode.whileWindowOpen.activationPolicy(windows: [mainWindow]), .regular)
        expectEqual(DockMode.always.activationPolicy(windows: []), .regular)
    },
    Test("startsAccessoryWithoutWindow") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let app = FakeApp()
                let dock = app.presence(defaults)
                expectEqual(dock.mode, .whileWindowOpen)
                expect(!dock.showsIcon)
                expectEqual(app.applied, [false], "politique posee une fois au demarrage")
                expectEqual(app.activations, 0)
                expectEqual(defaults.string(forKey: "EssaiDockMode"), "whileWindowOpen")
            }
        }
    },
    Test("windowOpensThenCloses") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let app = FakeApp()
                let dock = app.presence(defaults)
                app.windows = [mainWindow]
                dock.update()
                expect(dock.showsIcon)
                expectEqual(app.applied, [false, true])
                expectEqual(app.activations, 1, "la fenetre passe devant")
                dock.update()
                expectEqual(app.applied.count, 2, "rien ne change : rien n'est reapplique")
                expectEqual(app.activations, 1)
                app.windows = []
                dock.update()
                expect(!dock.showsIcon)
                expectEqual(app.applied, [false, true, false])
                expectEqual(app.activations, 1)
            }
        }
    },
    Test("windowOpenAtLaunchShowsIconAndActivates") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let app = FakeApp()
                app.windows = [mainWindow]
                let dock = app.presence(defaults)
                expect(dock.showsIcon)
                expectEqual(app.applied, [true])
                expectEqual(app.activations, 1)
            }
        }
    },
    Test("hiddenAppKeepsItsPolicy") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let app = FakeApp()
                app.windows = [mainWindow]
                let dock = app.presence(defaults)
                // Cmd-H : les fenetres ne sont plus visibles, mais l'icone reste (comme une app normale).
                app.hidden = true
                app.windows = []
                dock.update()
                expect(dock.showsIcon)
                expectEqual(app.applied, [true])
            }
        }
    },
    Test("alwaysModeKeepsIconWithoutActivating") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let app = FakeApp()
                let dock = app.presence(defaults)
                dock.mode = .always
                expect(dock.showsIcon)
                expectEqual(app.applied, [false, true])
                expectEqual(app.activations, 0, "changer de mode n'active pas l'app")
                expectEqual(defaults.string(forKey: "EssaiDockMode"), "always")
                app.windows = [mainWindow]
                dock.update()
                app.windows = []
                dock.update()
                expect(dock.showsIcon)
                expectEqual(app.applied, [false, true])
                dock.mode = .whileWindowOpen
                expect(!dock.showsIcon)
                expectEqual(app.applied, [false, true, false])
            }
        }
    },
    Test("storedModeIsRead") {
        MainActor.assumeIsolated {
            withDefaults { defaults in
                defaults.set("always", forKey: "EssaiDockMode")
                let app = FakeApp()
                let dock = app.presence(defaults)
                expectEqual(dock.mode, .always)
                expectEqual(app.applied, [true])
                expectEqual(app.activations, 0)
            }
        }
    },
    Test("realWindowsAreDescribed") {
        MainActor.assumeIsolated {
            let titled = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: true)
            titled.isReleasedWhenClosed = false
            let described = DockWindow(titled)
            expect(described.isTitled && described.isNormalLevel && !described.isAuxiliary)
            expect(!described.isVisible, "jamais montree")
            let panel = FloatingPanel(size: CGSize(width: 100, height: 100))
            let p = DockWindow(panel)
            expect(p.isAuxiliary && !p.isTitled && !p.isNormalLevel)
        }
    },
    Test("loginLaunchDoesNotStealFocus") {
        expect(DockPresence.mayActivate(launchedAsLoginItem: false, hasBeenActive: false))
        expect(!DockPresence.mayActivate(launchedAsLoginItem: true, hasBeenActive: false))
        expect(DockPresence.mayActivate(launchedAsLoginItem: true, hasBeenActive: true))
        MainActor.assumeIsolated {
            withDefaults { defaults in
                let app = FakeApp()
                app.windows = [mainWindow]
                let dock = app.presence(defaults, loginItem: true)
                expect(dock.showsIcon, "la fenetre ouverte a la connexion garde l'icone")
                expectEqual(app.activations, 0, "ouverture de session : pas de vol du focus")
                app.windows = []
                dock.update()
                dock.noteBecameActive()
                app.windows = [mainWindow]
                dock.update()
                expectEqual(app.activations, 1, "apres un premier passage au premier plan, la fenetre passe devant")
            }
        }
    },
    Test("windowBroughtForwardPrefersMainThenKey") {
        let hidden = DockWindow(isVisible: false, isMiniaturized: false, isTitled: true, isNormalLevel: true, isAuxiliary: false)
        let reduced = DockWindow(isVisible: false, isMiniaturized: true, isTitled: true, isNormalLevel: true, isAuxiliary: false)
        let panel = DockWindow(isVisible: true, isMiniaturized: false, isTitled: false, isNormalLevel: false, isAuxiliary: true)
        let windows = [panel, mainWindow, mainWindow, hidden, reduced]
        expectEqual(DockPresence.windowToFront(main: 2, key: 1, windows: windows), 2, "fenetre principale d'abord")
        expectEqual(DockPresence.windowToFront(main: 3, key: 1, windows: windows), 1, "principale fermee : la fenetre cle")
        expectEqual(DockPresence.windowToFront(main: 4, key: 0, windows: windows), 1, "principale reduite, cle = panneau : premiere comptee")
        expectEqual(DockPresence.windowToFront(main: nil, key: nil, windows: [panel, reduced]), nil)
    },
    Test("deactivatesOnlyWithoutAnyWindow") {
        expect(DockPresence.deactivates(showsIcon: false, visibleKeyableWindows: 0))
        expect(!DockPresence.deactivates(showsIcon: false, visibleKeyableWindows: 1), "panneau ou MenuBarExtra ouvert")
        expect(!DockPresence.deactivates(showsIcon: true, visibleKeyableWindows: 0))
    },
])
