import Foundation
@testable import VialetKit

private let allege = "fr.vialet.allege", pince = "fr.vialet.pince", pico = "fr.vialet.pico"
private let vialet = "fr.vialet.vialet"

private func role(_ me: String, vialet hub: Bool = false, installed: Set<String>, running: Set<String> = []) -> HubRole {
    HubElection.role(me: me, hubAppRunning: hub, installed: installed, runningHosts: running)
}

private func manifest(_ id: String, hub: Int?) -> HubManifest {
    let name = String(id.split(separator: ".").last!).capitalized
    var m = HubManifest(identity: AppIdentity(name: name, displayName: name, repository: "avialet/\(name.lowercased())",
                                              bundleIdentifier: id, palette: .sea, glyph: ""),
                        version: "0.2.6", appPath: "/Applications/\(name).app", scheme: name.lowercased(), actions: [])
    m.hub = hub
    return m
}

let hubElectionTests: (String, [Test]) = ("HubElection", [
    Test("runningVialetHostsEverything") {
        expectEqual(role(allege, vialet: true, installed: [allege]), .vialet)
        expectEqual(role(allege, vialet: true, installed: [allege, pince], running: [pince]), .vialet)
    },
    Test("aloneKeepsItsIcon") {
        expectEqual(role(allege, installed: [allege]), .alone)
        expectEqual(role(allege, installed: []), .alone, "version de developpement hors Applications : comptee quand meme")
        expectEqual(role(allege, installed: [allege, vialet]), .alone, "Vialet (non retenue par LaunchServices) ne compte pas")
    },
    Test("twoAppsElectTheSmallestRunningBundle") {
        expectEqual(role(allege, installed: [allege, pince]), .host, "seule a tourner : hote")
        expectEqual(role(pince, installed: [allege, pince]), .host, "Allege installee mais arretee : Pince tient le menu")
        expectEqual(role(pince, installed: [allege, pince], running: [allege]), .member(host: allege))
        expectEqual(role(allege, installed: [allege, pince], running: [pince]), .host)
        expectEqual(role(pince, installed: [allege, pince, pico], running: [pico]), .member(host: pico), "pico < pince")
        expectEqual(role(pico, installed: [allege, pince, pico], running: [pince]), .host)
    },
    Test("everyRunningAppAgreesOnOneHost") {
        let installed: Set<String> = [allege, pince, pico, "fr.vialet.brouillon"]
        let running: Set<String> = [pince, pico, "fr.vialet.brouillon"]
        let roles = running.map { role($0, installed: installed, running: running) }
        expectEqual(roles.filter { $0 == .host }.count, 1, "un seul hote")
        expectEqual(role("fr.vialet.brouillon", installed: installed, running: running), .host)
        expect(roles.allSatisfy { $0 == .host || $0 == .member(host: "fr.vialet.brouillon") })
    },
    Test("rolesDecideTheIcons") {
        expect(HubRole.alone.showsOwnIcon)
        expect(!HubRole.vialet.showsOwnIcon)
        expect(!HubRole.host.showsOwnIcon)
        expect(!HubRole.member(host: allege).showsOwnIcon)
        expect(HubRole.host.hostsHub)
        expect(!HubRole.alone.hostsHub && !HubRole.vialet.hostsHub && !HubRole.member(host: allege).hostsHub)
        expectEqual(HubRole(stored: HubRole.member(host: pince).stored), .member(host: pince))
        expectEqual(HubRole(stored: "host"), .host)
        expectEqual(HubRole(stored: "alone"), .alone)
        expectEqual(HubRole(stored: "vialet"), .vialet)
        expectEqual(HubRole(stored: "n'importe"), nil)
        expectEqual(HubRole(stored: nil), nil)
    },
    Test("userModesAlwaysWinForOwnIcon") {
        for r in [HubRole.alone, .vialet, .host, .member(host: allege)] {
            expect(MenuBarMode.shown.isInserted(role: r))
            expect(!MenuBarMode.hidden.isInserted(role: r))
            expectEqual(MenuBarMode.auto.isInserted(role: r), r.showsOwnIcon)
        }
        // L'ancienne regle est le cas particulier sans election.
        expectEqual(MenuBarMode.auto.isInserted(hubInstalled: true), MenuBarMode.auto.isInserted(role: .vialet))
        expectEqual(MenuBarMode.auto.isInserted(hubInstalled: false), MenuBarMode.auto.isInserted(role: .alone))
    },
    Test("statusExplainsTheRole") {
        expectEqual(MenuBarMode.auto.status(role: .vialet, hubName: "Vialet"),
                    "Masqu\u{00E9}e : Vialet tourne et rassemble les apps.")
        expectEqual(MenuBarMode.auto.status(role: .alone, hubName: "Vialet"),
                    "Visible : c'est la seule app vialet.app de ce Mac.")
        expectEqual(MenuBarMode.auto.status(role: .host, hubName: "Vialet"),
                    "Masqu\u{00E9}e : l'ic\u{00F4}ne vialet.app de la barre des menus rassemble les apps.")
        expectEqual(MenuBarMode.auto.status(role: .member(host: pince), hubName: "Vialet"),
                    MenuBarMode.auto.status(role: .host, hubName: "Vialet"))
        expectEqual(MenuBarMode.shown.status(role: .host, hubName: "Vialet"), "")
    },
    Test("candidatesComeFromValidatedManifestsWithTheHubFlag") {
        let manifests = [manifest(allege, hub: 1), manifest(pince, hub: nil), manifest(pico, hub: 2),
                         manifest("fr.vialet.fantome", hub: 1), manifest(vialet, hub: 1)]
        let installed: Set<String> = [allege, pince, pico, vialet]
        expectEqual(HubElection.capable(manifests: manifests, installed: installed), [allege, pico],
                    "fiche sans drapeau (kit < 0.2.6), app absente et Vialet ecartees")
        expectEqual(HubElection.counted(installed: [allege, pince, vialet]), [allege, pince])
    },
    Test("manifestHubFlagIsOptional") {
        let m = manifest(allege, hub: nil)
        let text = String(decoding: try m.encoded(), as: UTF8.self)
        expect(!text.contains("\"hub\""), text)
        expectEqual(HubManifest.decode(try m.encoded())?.hub, nil)
        expectEqual(HubManifest.decode(try manifest(allege, hub: 1).encoded())?.hub, 1)
    },
    Test("appActionsPublishTheHubFlagWhenHosting") {
        MainActor.assumeIsolated {
            let identity = AppIdentity(name: "Allege", displayName: "All\u{00E8}ge", repository: "avialet/allege",
                                       bundleIdentifier: allege, palette: .sea, glyph: "")
            let actions = AppActions(identity, open: {})
            expectEqual(actions.manifest().hub, nil)
            actions.hostsHub = true
            expectEqual(actions.manifest().hub, HubElection.protocolVersion)
        }
    },
    Test("menuBarPresenceFollowsTheRole") {
        MainActor.assumeIsolated {
            let suite = "VialetKitCheck.Election.\(UInt32.random(in: 0...UInt32.max))"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let identity = AppIdentity(name: "Essai", displayName: "Essai", repository: "avialet/essai",
                                       bundleIdentifier: "fr.vialet.essai", palette: .sea, glyph: "")
            let presence = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
            expectEqual(presence.hubRole, nil)
            expect(presence.isInserted, "sans election : l'ancienne regle")
            presence.hubRole = .member(host: allege)
            expect(!presence.isInserted)
            expectEqual(defaults.string(forKey: "EssaiHubRole"), "member:fr.vialet.allege")
            expectEqual(presence.status, "Masqu\u{00E9}e : l'ic\u{00F4}ne vialet.app de la barre des menus rassemble les apps.")
            presence.mode = .shown
            expect(presence.isInserted)
            // Au lancement suivant : le dernier role connu evite que l'icone n'apparaisse puis disparaisse.
            let next = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
            expectEqual(next.hubRole, .member(host: allege))
            next.mode = .auto
            expect(!next.isInserted)
        }
    },
])

/// Icone vialet.app pilotee par le test.
@MainActor
private final class FakeHosting: HubHosting {
    var log: [String] = []
    func show() { log.append("show") }
    func hide() { log.append("hide") }
}

let hubPresenceTests: (String, [Test]) = ("HubPresence", [
    Test("factsGiveTheRole") {
        let facts = HubFacts(me: pince, installed: [allege, pince, vialet],
                             capable: [allege, pince], running: [allege, pince])
        expectEqual(facts.role, .member(host: allege))
        var stopped = facts
        stopped.running = [pince]
        expectEqual(stopped.role, .host, "l'hote a quitte : Pince reprend")
        var old = facts
        old.capable = [pince]
        expectEqual(old.role, .host, "Allege au kit ancien ne peut pas heberger : elle garde son icone, Pince rassemble")
        expect(!facts.hubAppRunning, "Vialet installee mais arretee : election entre les apps")
        var withVialet = facts
        withVialet.running.insert(vialet)
        expect(withVialet.hubAppRunning)
        expectEqual(withVialet.role, .vialet, "Vialet tourne : elle rassemble")
    },
    Test("applyShowsAndHidesTheHubOnce") {
        MainActor.assumeIsolated {
            let suite = "VialetKitCheck.HubPresence.\(UInt32.random(in: 0...UInt32.max))"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            let identity = AppIdentity(name: "Pince", displayName: "Pince", repository: "avialet/pince",
                                       bundleIdentifier: pince, palette: .sea, glyph: "")
            let menuBar = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
            let hosting = FakeHosting()
            var announced = 0
            let presence = HubPresence(menuBar: menuBar, actions: AppActions(identity, open: {}), hosting: hosting,
                                       statusItem: nil, announce: { announced += 1 })
            expectEqual(presence.role, .alone, "aucun role connu : seule")
            presence.apply(.host)
            presence.apply(.host)
            expectEqual(hosting.log, ["show"])
            expectEqual(announced, 1)
            expectEqual(menuBar.hubRole, .host)
            expect(!menuBar.isInserted, "hote : son icone laisse place a vialet.app")
            presence.apply(.member(host: allege))
            expectEqual(hosting.log, ["show", "hide"])
            expectEqual(announced, 2)
            presence.apply(.alone)
            expectEqual(hosting.log, ["show", "hide"])
            expectEqual(announced, 2, "pas d'annonce sans changement d'hote")
            expect(menuBar.isInserted)
            // Au lancement suivant, le dernier role connu s'applique avant l'election.
            let again = HubPresence(menuBar: MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false),
                                    actions: AppActions(identity, open: {}), hosting: FakeHosting(), statusItem: nil, announce: {})
            expectEqual(again.role, .alone)
        }
    },
    Test("onlyProcessesInsideApplicationsCount") {
        let roots = [URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/Users/a/Applications")]
        func p(_ id: String?, _ path: String?, terminated: Bool = false) -> HubProcess {
            HubProcess(bundleIdentifier: id, bundleURL: path.map { URL(fileURLWithPath: $0) }, isTerminated: terminated)
        }
        let processes = [p(allege, "/Applications/Allege.app"), p(pince, "/Users/a/Applications/Pince.app"),
                         p(vialet, "/Users/a/Downloads/Vialet.app"), p(pico, "/Applications/Pico.app", terminated: true),
                         p("fr.vialet.brouillon", nil), p("com.apple.finder", "/System/Library/CoreServices/Finder.app"),
                         p(nil, "/Applications/Sans.app"), p("fr.vialet.chuchote", "/Applications/Chuchote.app")]
        expectEqual(HubElection.running(processes, roots: roots, ended: ["fr.vialet.chuchote"]), [allege, pince],
                    "usurpation hors Applications, termine, sans bundle, autre editeur et app qui vient de quitter ecartes")
        let facts = HubFacts(me: pince, installed: [allege, pince], capable: [allege, pince],
                             running: HubElection.running(processes, roots: roots, ended: []))
        expect(!facts.hubAppRunning, "un faux Vialet hors Applications ne prend pas la main")
    },
    Test("scansAreSpacedByTwoSeconds") {
        let t0 = Date(timeIntervalSince1970: 1000)
        expectEqual(HubElection.scanDelay(requested: 0.4, now: t0, lastScan: nil), 0.4)
        expectEqual(HubElection.scanDelay(requested: 0.4, now: t0, lastScan: t0.addingTimeInterval(-10)), 0.4)
        expectEqual(HubElection.scanDelay(requested: 0.4, now: t0, lastScan: t0.addingTimeInterval(-0.5)), 1.5)
        expectEqual(HubElection.scanDelay(requested: 0.4, now: t0, lastScan: t0), 2)
        expectEqual(HubElection.scanDelay(requested: 0.4, now: t0, lastScan: t0.addingTimeInterval(5)), 0.4, "horloge reculee")
        expectEqual(HubElection.minScanInterval, 2)
    },
    Test("rememberedHostStepsAsideForARunningHost") {
        expectEqual(HubElection.initialRole(stored: nil, me: pince, hubAppRunning: false, runningHosts: []), .alone)
        expectEqual(HubElection.initialRole(stored: .host, me: pince, hubAppRunning: false, runningHosts: []), .host)
        expectEqual(HubElection.initialRole(stored: .host, me: pince, hubAppRunning: false, runningHosts: [allege]),
                    .member(host: allege), "Allege tient deja le menu")
        expectEqual(HubElection.initialRole(stored: .host, me: allege, hubAppRunning: false, runningHosts: [pince]), .host,
                    "plus petit bundle : reste hote")
        expectEqual(HubElection.initialRole(stored: .host, me: pince, hubAppRunning: true, runningHosts: []), .vialet)
        expectEqual(HubElection.initialRole(stored: .member(host: allege), me: pince, hubAppRunning: false, runningHosts: []),
                    .member(host: allege))
    },
    Test("appOutsideApplicationsKeepsItsIconWithoutElection") {
        MainActor.assumeIsolated {
            let suite = "VialetKitCheck.HubOutside.\(UInt32.random(in: 0...UInt32.max))"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set("host", forKey: "PinceHubRole")
            let identity = AppIdentity(name: "Pince", displayName: "Pince", repository: "avialet/pince",
                                       bundleIdentifier: pince, palette: .sea, glyph: "")
            let menuBar = MenuBarPresence(app: identity, defaults: defaults, hubLocator: { false }, observe: false)
            let hosting = FakeHosting()
            var announced = 0
            let actions = AppActions(identity, open: {})
            let presence = HubPresence(menuBar: menuBar, actions: actions, hosting: hosting, statusItem: nil,
                                       announce: { announced += 1 })
            presence.begin(inApplications: false)
            expectEqual(presence.role, .alone)
            expectEqual(menuBar.hubRole, .alone)
            expect(menuBar.isInserted, "image disque, Telechargements : l'app garde son icone")
            expectEqual(hosting.log, [], "ni menu rassembleur")
            expectEqual(announced, 0, "ni election")
            expect(!actions.hostsHub, "la fiche ne se dit pas hote")
            expectEqual(defaults.string(forKey: "PinceHubRole"), "host", "le role memorise n'est pas ecrase")
        }
    },
])
