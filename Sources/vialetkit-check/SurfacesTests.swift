import AppKit
import SwiftUI
import VialetKit

/// Identite jetable : cles UserDefaults uniques, effacees apres chaque test.
@MainActor
private func withTestApp(_ body: (AppIdentity, HotKeyController, Updater) -> Void) {
    let name = "VialetKitCheck\(UInt32.random(in: 0...UInt32.max))"
    let identity = AppIdentity(name: name, displayName: "Essai", repository: "avialet/essai",
                               bundleIdentifier: "fr.vialet.essai", palette: .sea, glyph: "")
    let suffixes = ["HotKey", "Appearance", "AutoUpdate", "LastUpdateCheck", "MenuBar"]
    defer { for s in suffixes { UserDefaults.standard.removeObject(forKey: identity.key(s)) } }
    let hotKey = HotKeyController(defaultsKey: identity.key("HotKey"), logName: name,
                                  initial: .space([.control, .shift]))
    let updater = Updater(configuration: UpdaterConfiguration(identity))
    body(identity, hotKey, updater)
}

/// Taille ideale d'une vue, mesuree par un NSHostingView.
@MainActor
private func fittingSize<V: View>(_ view: V) -> CGSize {
    NSHostingView(rootView: view).fittingSize
}

let surfacesTests: (String, [Test]) = ("Surfaces", [
    Test("smallViewsBuildAndLayOut") {
        MainActor.assumeIsolated {
            let views: [(String, CGSize)] = [
                ("Wordmark", fittingSize(Wordmark("Pince"))),
                ("Wordmark 40", fittingSize(Wordmark("Pince", size: 40))),
                ("Mini", fittingSize(Wordmark.Mini("Pince"))),
                ("SectionHeader", fittingSize(SectionHeader("Aujourd'hui"))),
                ("KeyHint", fittingSize(KeyHint("esc", "fermer"))),
                ("ShortcutFooter", fittingSize(ShortcutFooter(.default))),
                ("PanelCard", fittingSize(PanelCard { Text("x").frame(width: 120, height: 40) })),
            ]
            for (name, size) in views {
                expect(size.width > 0 && size.height > 0, "\(name) vide : \(size)")
            }
            expect(fittingSize(Wordmark("Pince", size: 40)).height > fittingSize(Wordmark("Pince")).height,
                   "la taille du wordmark suit size")
        }
    },
    Test("panelCardKeepsContentSize") {
        MainActor.assumeIsolated {
            let size = fittingSize(PanelCard { Color.clear.frame(width: 120, height: 40) })
            expectEqual(size, CGSize(width: 120, height: 40))
        }
    },
    Test("settingsScreenWidth") {
        MainActor.assumeIsolated {
            withTestApp { identity, hotKey, updater in
                let standard = SettingsScreen(app: identity, hotKey: hotKey, updater: updater,
                                              menuBarVisible: .constant(true), hotKeyHint: "Indice")
                let size = fittingSize(standard)
                expectEqual(size.width, 460)
                expect(size.height > 300, "hauteur \(size.height)")

                let wide = SettingsScreen(app: identity, hotKey: hotKey, updater: updater,
                                          menuBarVisible: .constant(false), hotKeyHint: "Indice", width: 480) {
                    SettingsCard(icon: "doc.on.clipboard", color: Theme.accent, title: "Historique") {
                        Text("Contenu propre a l'app").frame(height: 200)
                    }
                }
                let wideSize = fittingSize(wide)
                expectEqual(wideSize.width, 480)
                expect(wideSize.height > size.height + 200, "la carte extra s'ajoute : \(wideSize.height)")
            }
        }
    },
])
