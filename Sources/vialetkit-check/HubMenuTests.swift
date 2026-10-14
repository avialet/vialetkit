import AppKit
import SwiftUI
@testable import VialetKit

private let vialetIdentity = AppIdentity(name: "Vialet", displayName: "Vialet", repository: "avialet/vialet",
                                         bundleIdentifier: "fr.vialet.vialet", palette: .sea, glyph: "",
                                         site: URL(string: "https://vialet.app")!)

@MainActor
private func entry(_ name: String, status: String? = nil, active: Bool = false, actions: [AppAction] = []) -> HubEntry {
    HubEntry(bundleIdentifier: "fr.vialet.\(name.lowercased())", name: name, displayName: name, version: "0.2.0",
             appURL: URL(fileURLWithPath: "/Applications/\(name).app"), scheme: name.lowercased(),
             repository: "avialet/\(name.lowercased())", site: nil, palette: .sea, glyph: "M 20 50 L 80 50",
             strokeDeep: false, actions: actions, tagline: "Accroche", status: status, active: active)
}

@MainActor
private func height(_ model: HubModel, _ options: HubMenuOptions = HubMenuOptions()) -> CGFloat {
    NSHostingView(rootView: HubMenu(model: model, options: options)).fittingSize.height
}

let hubMenuTests: (String, [Test]) = ("HubMenu", [
    Test("modelKeysAreThoseOfVialet0_1") {
        MainActor.assumeIsolated {
            let model = HubModel(identity: vialetIdentity, updater: Updater(configuration: UpdaterConfiguration(vialetIdentity)),
                                 announcesOwnUpdate: true)
            expectEqual(model.defaultsKeys, ["VialetLastAppsCheck", "VialetCatalogFetched", "VialetAppUpdates", "VialetReleaseETags"])
        }
    },
    Test("backgroundActionsDoNotActivate") {
        expect(!HubModel.activates(bundleIdentifier: "fr.vialet.chuchote", action: "dicter"))
        expect(HubModel.activates(bundleIdentifier: "fr.vialet.chuchote", action: "ouvrir"))
        expect(HubModel.activates(bundleIdentifier: "fr.vialet.pico", action: "dicter"))
    },
    Test("menuShowsStatusAndFooterOptions") {
        MainActor.assumeIsolated {
            let updater = Updater(configuration: UpdaterConfiguration(vialetIdentity))
            let model = HubModel(identity: vialetIdentity, updater: updater)
            let actions = [AppAction("1h", title: "1 h", symbol: "sun.max", visible: .idle),
                           AppAction("stop", title: "Arr\u{00EA}ter", symbol: "stop.circle", visible: .active)]
            model.preview(HubListing(apps: [entry("Eveil", actions: actions)], discover: []), updates: [:])
            let idle = height(model)
            model.preview(HubListing(apps: [entry("Eveil", status: "\u{00C9}veill\u{00E9} jusqu'\u{00E0} 15 h 40", active: true,
                                                  actions: actions)], discover: []), updates: [:])
            let busy = height(model)
            expect(busy > idle + 8, "la ligne de statut s'ajoute : \(busy) / \(idle)")
            let full = height(model, HubMenuOptions(openSettings: {}, quitTitle: "Quitter Vialet"))
            expect(full > busy + 30, "Reglages et Quitter : \(full) / \(busy)")
        }
    },
    Test("statusIconIsTemplate") {
        MainActor.assumeIsolated {
            let image = HubStatusIcon.image()
            expect(image.isTemplate)
            expectEqual(image.size, NSSize(width: 18, height: 18))
        }
    },
    Test("statusItemTrackingEndsWithItsInstallation") {
        MainActor.assumeIsolated {
            let model = HubModel(identity: vialetIdentity, updater: Updater(configuration: UpdaterConfiguration(vialetIdentity)))
            model.preview(.empty, updates: [:])
            let item = HubStatusItem(model: model, autosaveName: "VialetKitCheck")
            item.install()
            let first = item.trackingGeneration
            expect(item.isInstalled)
            item.install()
            expectEqual(item.trackingGeneration, first, "deja posee : rien ne change")
            item.remove()
            expect(!item.isInstalled)
            item.install()
            expect(item.trackingGeneration > first + 1, "nouvelle pose : l'ancien suivi est perime")
            item.remove()
        }
    },
])
